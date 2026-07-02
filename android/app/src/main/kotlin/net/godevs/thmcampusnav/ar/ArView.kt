package net.godevs.thmcampusnav.ar

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.google.ar.core.Anchor
import com.google.ar.core.Camera
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import net.godevs.thmcampusnav.ar.helpers.DisplayRotationHelper
import net.godevs.thmcampusnav.ar.rendering.BackgroundRenderer
import net.godevs.thmcampusnav.ar.rendering.BeaconRenderer
import net.godevs.thmcampusnav.ar.rendering.MarkerRenderer
import net.godevs.thmcampusnav.ar.rendering.PlaneRenderer
import net.godevs.thmcampusnav.ar.rendering.RouteRenderer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A Flutter [PlatformView] that hosts a live ARCore session with horizontal
 * plane detection. It renders the camera feed, detected planes, and — when a
 * walking route + live device pose are supplied from Flutter — a ground-hugging
 * route ribbon and a destination beacon, geo-aligned so they stay locked to the
 * real world as the user looks around 360°.
 */
class ArView(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    messenger: BinaryMessenger,
    viewId: Int,
    channelBase: String,
) : PlatformView, GLSurfaceView.Renderer, DefaultLifecycleObserver {

    private val glSurfaceView = GLSurfaceView(context)
    private val channel = MethodChannel(messenger, "$channelBase/view_$viewId")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val displayRotationHelper = DisplayRotationHelper(context)

    private val backgroundRenderer = BackgroundRenderer()
    private val planeRenderer = PlaneRenderer()
    private val markerRenderer = MarkerRenderer()
    private val routeRenderer = RouteRenderer()
    private val beaconRenderer = BeaconRenderer()

    private var session: Session? = null
    private var glInitialised = false
    private var viewportWidth = 0
    private var viewportHeight = 0

    private var anchor: Anchor? = null

    private val viewMatrix = FloatArray(16)
    private val projMatrix = FloatArray(16)
    private val viewProjMatrix = FloatArray(16)
    private val anchorMatrix = FloatArray(16)

    private var phase = 0f

    // Geo data pushed from Flutter (read on the GL thread; written on main).
    @Volatile private var routeGeo: DoubleArray? = null // flat [lat,lng,...]
    @Volatile private var destGeo: DoubleArray? = null  // [lat,lng]
    @Volatile private var pose: DoubleArray? = null      // [lat,lng,headingDeg]

    private var lastTrackingState = ""
    private var lastPlaneCount = -1

    init {
        glSurfaceView.preserveEGLContextOnPause = true
        glSurfaceView.setEGLContextClientVersion(3)
        glSurfaceView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        glSurfaceView.setRenderer(this)
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        glSurfaceView.setWillNotDraw(false)
        glSurfaceView.keepScreenOn = true
        channel.setMethodCallHandler(::onMethodCall)
        lifecycleOwner.lifecycle.addObserver(this)
    }

    override fun getView(): View = glSurfaceView

    override fun dispose() {
        lifecycleOwner.lifecycle.removeObserver(this)
        pauseAr()
        session?.close()
        session = null
        channel.setMethodCallHandler(null)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setRoute" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as Map<String, Any?>
                val pts = args["points"] as List<*>
                val flat = DoubleArray(pts.size * 2)
                pts.forEachIndexed { i, e ->
                    val pair = e as List<*>
                    flat[i * 2] = (pair[0] as Number).toDouble()
                    flat[i * 2 + 1] = (pair[1] as Number).toDouble()
                }
                routeGeo = flat
                destGeo = doubleArrayOf(
                    (args["destLat"] as Number).toDouble(),
                    (args["destLng"] as Number).toDouble(),
                )
                result.success(null)
            }
            "updatePose" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as Map<String, Any?>
                pose = doubleArrayOf(
                    (args["lat"] as Number).toDouble(),
                    (args["lng"] as Number).toDouble(),
                    (args["heading"] as Number).toDouble(),
                )
                result.success(null)
            }
            "clearRoute" -> {
                routeGeo = null
                destGeo = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // region Lifecycle
    override fun onResume(owner: LifecycleOwner) = resumeAr()

    override fun onPause(owner: LifecycleOwner) = pauseAr()

    private fun resumeAr() {
        if (session == null) {
            try {
                session = Session(context).also { s ->
                    val config = Config(s).apply {
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                        lightEstimationMode = Config.LightEstimationMode.DISABLED
                        focusMode = Config.FocusMode.AUTO
                    }
                    s.configure(config)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to create ARCore session", t)
                reportStatus("stopped", 0)
                return
            }
        }
        try {
            session?.resume()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to resume ARCore session", t)
            session?.close()
            session = null
            reportStatus("stopped", 0)
            return
        }
        glSurfaceView.onResume()
        displayRotationHelper.onResume()
    }

    private fun pauseAr() {
        displayRotationHelper.onPause()
        glSurfaceView.onPause()
        session?.pause()
    }
    // endregion

    // region GLSurfaceView.Renderer
    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        try {
            backgroundRenderer.createOnGlThread()
            planeRenderer.createOnGlThread()
            markerRenderer.createOnGlThread()
            routeRenderer.createOnGlThread()
            beaconRenderer.createOnGlThread()
            glInitialised = true
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to initialise GL renderers", t)
        }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        viewportWidth = width
        viewportHeight = height
        displayRotationHelper.onSurfaceChanged(width, height)
        GLES20.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        val session = this.session ?: return
        if (!glInitialised) return

        try {
            session.setCameraTextureName(backgroundRenderer.textureId)
            displayRotationHelper.updateSessionIfNeeded(session)

            val frame = session.update()
            val camera = frame.camera

            backgroundRenderer.draw(frame)

            if (camera.trackingState == TrackingState.TRACKING) {
                camera.getViewMatrix(viewMatrix, 0)
                camera.getProjectionMatrix(projMatrix, 0, 0.1f, 500f)
                Matrix.multiplyMM(viewProjMatrix, 0, projMatrix, 0, viewMatrix, 0)

                val planes = session.getAllTrackables(Plane::class.java)
                planeRenderer.draw(planes, viewMatrix, projMatrix)

                if (anchor == null) tryPlaceAnchor(frame)
                val groundY = resolveGroundY(camera, planes)
                anchor?.let { a ->
                    if (a.trackingState == TrackingState.TRACKING) {
                        a.pose.toMatrix(anchorMatrix, 0)
                        markerRenderer.draw(anchorMatrix, viewMatrix, projMatrix)
                    }
                }

                renderRoute(camera, groundY)

                phase += 0.015f
                if (phase > 1_000_000f) phase = 0f

                reportStatus("tracking", countActivePlanes(planes))
            } else {
                reportStatus("paused", 0)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Exception on the GL thread", t)
        }
    }
    // endregion

    /**
     * Projects the route (and destination) from geographic coordinates into the
     * ARCore world frame and renders them on the ground.
     *
     * Alignment is derived every frame from the camera's own forward/right axes
     * and the device compass heading, which makes the mapping rotation-invariant:
     * as the user pans the phone, the ribbon and beacon stay locked to their real
     * geographic positions.
     */
    private fun renderRoute(camera: Camera, groundY: Float) {
        val route = routeGeo ?: return
        val p = pose ?: return
        if (route.size < 4) return

        val userLat = p[0]
        val userLng = p[1]
        val headingRad = Math.toRadians(p[2])

        val camPose = camera.pose
        val camX = camPose.tx().toDouble()
        val camZ = camPose.tz().toDouble()

        // Camera horizontal forward (-Z axis) and right (+X axis).
        val z = camPose.zAxis
        val x = camPose.xAxis
        var fX = -z[0].toDouble()
        var fZ = -z[2].toDouble()
        var rX = x[0].toDouble()
        var rZ = x[2].toDouble()
        var fLen = sqrt(fX * fX + fZ * fZ)
        var rLen = sqrt(rX * rX + rZ * rZ)
        if (fLen < 1e-6 || rLen < 1e-6) return
        fX /= fLen; fZ /= fLen
        rX /= rLen; rZ /= rLen

        val sinH = sin(headingRad)
        val cosH = cos(headingRad)

        // World directions for geographic East and North.
        var eastX = fX * sinH + rX * cosH
        var eastZ = fZ * sinH + rZ * cosH
        var northX = fX * cosH - rX * sinH
        var northZ = fZ * cosH - rZ * sinH
        val eLen = sqrt(eastX * eastX + eastZ * eastZ)
        val nLen = sqrt(northX * northX + northZ * northZ)
        if (eLen < 1e-6 || nLen < 1e-6) return
        eastX /= eLen; eastZ /= eLen
        northX /= nLen; northZ /= nLen

        val mPerDegLat = 111_320.0
        val mPerDegLng = 111_320.0 * cos(Math.toRadians(userLat))

        val count = route.size / 2
        val world = FloatArray(count * 3)
        for (i in 0 until count) {
            val lat = route[i * 2]
            val lng = route[i * 2 + 1]
            val north = (lat - userLat) * mPerDegLat
            val east = (lng - userLng) * mPerDegLng
            world[i * 3] = (camX + east * eastX + north * northX).toFloat()
            world[i * 3 + 1] = groundY
            world[i * 3 + 2] = (camZ + east * eastZ + north * northZ).toFloat()
        }
        routeRenderer.draw(world, count, viewProjMatrix, phase)

        destGeo?.let { d ->
            val north = (d[0] - userLat) * mPerDegLat
            val east = (d[1] - userLng) * mPerDegLng
            val bx = (camX + east * eastX + north * northX).toFloat()
            val bz = (camZ + east * eastZ + north * northZ).toFloat()
            beaconRenderer.draw(bx, groundY, bz, viewProjMatrix, phase)
        }
    }

    private fun resolveGroundY(camera: Camera, planes: Collection<Plane>): Float {
        anchor?.let { if (it.trackingState == TrackingState.TRACKING) return it.pose.ty() }
        for (plane in planes) {
            if (plane.trackingState == TrackingState.TRACKING && plane.subsumedBy == null) {
                return plane.centerPose.ty()
            }
        }
        return camera.pose.ty() - 1.4f
    }

    private fun tryPlaceAnchor(frame: Frame) {
        if (viewportWidth == 0 || viewportHeight == 0) return
        val cx = viewportWidth / 2f
        val cy = viewportHeight / 2f
        for (hit in frame.hitTest(cx, cy)) {
            val trackable = hit.trackable
            if (trackable is Plane &&
                trackable.trackingState == TrackingState.TRACKING &&
                trackable.isPoseInPolygon(hit.hitPose)
            ) {
                anchor = hit.createAnchor()
                return
            }
        }
    }

    private fun countActivePlanes(planes: Collection<Plane>): Int {
        var count = 0
        for (p in planes) {
            if (p.trackingState == TrackingState.TRACKING && p.subsumedBy == null) count++
        }
        return count
    }

    private fun reportStatus(trackingState: String, planeCount: Int) {
        if (trackingState == lastTrackingState && planeCount == lastPlaneCount) return
        lastTrackingState = trackingState
        lastPlaneCount = planeCount
        mainHandler.post {
            try {
                channel.invokeMethod(
                    "status",
                    mapOf("trackingState" to trackingState, "planeCount" to planeCount),
                )
            } catch (_: Throwable) {
                // View may already be detached; ignore.
            }
        }
    }

    companion object {
        private const val TAG = "ArView"
    }
}

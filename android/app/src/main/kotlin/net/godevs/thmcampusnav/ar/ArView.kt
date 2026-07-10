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
import net.godevs.thmcampusnav.ar.rendering.BillboardTextRenderer
import net.godevs.thmcampusnav.ar.rendering.GroundArrowRenderer
import net.godevs.thmcampusnav.ar.rendering.MarkerRenderer
import net.godevs.thmcampusnav.ar.rendering.PinRenderer
import net.godevs.thmcampusnav.ar.rendering.PlaneRenderer
import net.godevs.thmcampusnav.ar.rendering.RouteRenderer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
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
    private val groundArrowRenderer = GroundArrowRenderer()
    private val pinRenderer = PinRenderer()
    private val infoLabel = BillboardTextRenderer()
    private val destLabel = BillboardTextRenderer()

    private var session: Session? = null
    private var glInitialised = false
    private var viewportWidth = 0
    private var viewportHeight = 0

    private var anchor: Anchor? = null

    private val viewMatrix = FloatArray(16)
    private val projMatrix = FloatArray(16)
    private val viewProjMatrix = FloatArray(16)

    private var phase = 0f

    // Geo data pushed from Flutter (read on the GL thread; written on main).
    @Volatile private var routeGeo: DoubleArray? = null // flat [lat,lng,...]
    @Volatile private var destGeo: DoubleArray? = null  // [lat,lng]
    @Volatile private var pose: DoubleArray? = null      // [lat,lng,headingDeg]

    // Guidance text drawn as 3D labels (written on main; read on the GL thread).
    @Volatile private var distanceText: String? = null
    @Volatile private var stepsText: String? = null
    @Volatile private var etaText: String? = null
    @Volatile private var destName: String? = null

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
            "updateGuidance" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as Map<String, Any?>
                distanceText = args["distanceText"] as String?
                stepsText = args["stepsText"] as String?
                etaText = args["etaText"] as String?
                destName = args["destName"] as String?
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
            groundArrowRenderer.createOnGlThread()
            pinRenderer.createOnGlThread()
            infoLabel.createOnGlThread()
            destLabel.createOnGlThread()
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
                maybePlaceAnchor(frame)

                // Resolve the true ground height under the camera and lock the
                // chevrons/pin/card to it, so everything sits ON the road instead
                // of floating. Falls back to an eye-height estimate before a
                // plane is found, so guidance appears immediately at foot level.
                // The plane grid and anchor disc are intentionally NOT drawn — a
                // clean camera view with only the guidance objects reads far more
                // professionally than surfaces scribbled all over the scene.
                val groundY = resolveGroundY(planes, camera.pose.ty())
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
     * Renders the professional guidance scene, geo-aligned to the real world:
     *  1. flowing **3D chevrons** on the road for the next ~12 m (walk this way),
     *  2. a **3D map pin** floating toward the destination building (which side),
     *  3. one **info card** (distance · steps · ETA) above the road ahead.
     *
     * The east/north basis is derived every frame from the camera axes and the
     * compass heading, so the mapping is rotation-invariant: as the user pans the
     * phone, everything stays locked to its real geographic position.
     */
    private fun renderRoute(camera: Camera, groundY: Float) {
        val p = pose ?: return

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
        val fLen = sqrt(fX * fX + fZ * fZ)
        val rLen = sqrt(rX * rX + rZ * rZ)
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

        val ux = camX.toFloat()
        val uz = camZ.toFloat()
        val camRight = camPose.xAxis
        val camUp = camPose.yAxis

        // Forward direction to place the card; set by the near route if present.
        var forwardDx = (fX).toFloat()
        var forwardDz = (fZ).toFloat()

        // 1) Flowing 3D chevrons along the immediate route ahead.
        val route = routeGeo
        if (route != null && route.size >= 4) {
            val count = route.size / 2
            val world = FloatArray(count * 2)
            for (i in 0 until count) {
                val north = (route[i * 2] - userLat) * mPerDegLat
                val east = (route[i * 2 + 1] - userLng) * mPerDegLng
                world[i * 2] = (camX + east * eastX + north * northX).toFloat()
                world[i * 2 + 1] = (camZ + east * eastZ + north * northZ).toFloat()
            }
            val dir = drawForwardChevrons(world, count, ux, uz, groundY)
            if (dir != null) {
                forwardDx = dir[0]
                forwardDz = dir[1]
            }
        }

        // 2) Destination map pin (clamped near enough to always be visible) with
        //    a camera-facing name + distance label above it.
        destGeo?.let { d ->
            val north = (d[0] - userLat) * mPerDegLat
            val east = (d[1] - userLng) * mPerDegLng
            val dxW = (camX + east * eastX + north * northX).toFloat()
            val dzW = (camZ + east * eastZ + north * northZ).toFloat()
            var vx = dxW - ux
            var vz = dzW - uz
            val dist = sqrt(vx * vx + vz * vz)
            val shown = min(dist, 24f)
            val pinX: Float
            val pinZ: Float
            if (dist > 1e-3f) {
                pinX = ux + vx / dist * shown
                pinZ = uz + vz / dist * shown
            } else {
                pinX = dxW
                pinZ = dzW
            }
            // Warm red pin — the universal "destination" marker.
            pinRenderer.draw(pinX, groundY, pinZ, viewProjMatrix, phase, 1.2f,
                0.95f, 0.28f, 0.30f)

            destName?.let { name ->
                val dText = distanceText
                val label = if (dText != null) "$name   •   $dText" else name
                destLabel.setText(label)
                destLabel.draw(pinX, groundY + 3.4f, pinZ,
                    camRight, camUp, viewProjMatrix, 0.9f)
            }
        }

        // 3) One professional info card floating just above the road ahead.
        val dText = distanceText
        val sText = stepsText
        if (dText != null && sText != null) {
            val ahead = 4.5f
            val ax = ux + forwardDx * ahead
            val az = uz + forwardDz * ahead
            val sub = etaText?.let { "$sText  ·  $it" } ?: sText
            infoLabel.setCard(destName ?: "Destination", dText, sub)
            infoLabel.draw(ax, groundY + 1.45f, az,
                camRight, camUp, viewProjMatrix, 1.15f)
        }
    }

    /**
     * Draws flowing 3D chevrons for the next ~12 m of the route ahead of the
     * user's nearest point on the path. Returns the initial forward unit
     * direction (XZ) so the info card can be placed along it, or null.
     */
    private fun drawForwardChevrons(
        world: FloatArray,
        count: Int,
        ux: Float,
        uz: Float,
        groundY: Float,
    ): FloatArray? {
        if (count < 2) return null

        // Nearest point on the polyline to the user → start just ahead of it.
        var bestSeg = 0
        var bestT = 0f
        var bestD2 = Float.MAX_VALUE
        for (i in 0 until count - 1) {
            val ax = world[i * 2]; val az = world[i * 2 + 1]
            val dx = world[(i + 1) * 2] - ax; val dz = world[(i + 1) * 2 + 1] - az
            val len2 = dx * dx + dz * dz
            var t = 0f
            if (len2 > 1e-6f) t = (((ux - ax) * dx + (uz - az) * dz) / len2).coerceIn(0f, 1f)
            val px = ax + dx * t; val pz = az + dz * t
            val d2 = (px - ux) * (px - ux) + (pz - uz) * (pz - uz)
            if (d2 < bestD2) { bestD2 = d2; bestSeg = i; bestT = t }
        }

        var s0 = 0f
        for (i in 0 until bestSeg) {
            val ax = world[i * 2]; val az = world[i * 2 + 1]
            val dx = world[(i + 1) * 2] - ax; val dz = world[(i + 1) * 2 + 1] - az
            s0 += sqrt(dx * dx + dz * dz)
        }
        run {
            val ax = world[bestSeg * 2]; val az = world[bestSeg * 2 + 1]
            val dx = world[(bestSeg + 1) * 2] - ax; val dz = world[(bestSeg + 1) * 2 + 1] - az
            s0 += sqrt(dx * dx + dz * dz) * bestT
        }

        val spacing = 2.4f
        val ahead = 12f
        val arrowY = groundY + 0.02f
        var firstDir: FloatArray? = null
        var emit = 1.2f
        while (emit <= ahead) {
            val pd = pointAndDir(world, count, s0 + emit) ?: break
            if (firstDir == null) firstDir = floatArrayOf(pd[2], pd[3])
            val headingDeg = Math.toDegrees(atan2(pd[2].toDouble(), pd[3].toDouble())).toFloat()
            // Highlight band that flows forward over time.
            var cp = (emit * 0.18f - phase * 0.9f) % 1f
            if (cp < 0f) cp += 1f
            val glow = (1f - min(cp, 1f - cp) * 3f).coerceIn(0f, 1f)
            groundArrowRenderer.draw(
                pd[0], arrowY, pd[1], headingDeg, viewProjMatrix, 0.9f,
                0.0f, 0.60f + 0.35f * glow, 0.45f + 0.45f * glow, 0.60f + 0.40f * glow,
            )
            emit += spacing
        }
        return firstDir
    }

    /**
     * [x, z, dirX, dirZ] at cumulative distance [s] along the world polyline,
     * with the direction normalised; null once past the end of the path.
     */
    private fun pointAndDir(world: FloatArray, count: Int, s: Float): FloatArray? {
        if (count < 2) return null
        var acc = 0f
        for (i in 0 until count - 1) {
            val ax = world[i * 2]; val az = world[i * 2 + 1]
            val dx = world[(i + 1) * 2] - ax; val dz = world[(i + 1) * 2 + 1] - az
            val segLen = sqrt(dx * dx + dz * dz)
            if (segLen < 1e-4f) continue
            if (acc + segLen >= s) {
                val t = ((s - acc) / segLen).coerceIn(0f, 1f)
                return floatArrayOf(ax + dx * t, az + dz * t, dx / segLen, dz / segLen)
            }
            acc += segLen
        }
        return null
    }

    /**
     * True ground height under the camera. Prefers the anchor / a tracked
     * upward-facing horizontal plane, but only accepts heights within a band
     * around the expected ground ([cameraY] − eye height) — so ARCore locking
     * onto a wall, table, or planter can't lift the whole route into the air.
     * Falls back to the eye-height estimate so guidance still appears at foot
     * level before a plane is found.
     */
    private fun resolveGroundY(planes: Collection<Plane>, cameraY: Float): Float {
        val expected = cameraY - EYE_HEIGHT
        val band = 0.7f

        anchor?.let { a ->
            if (a.trackingState == TrackingState.TRACKING) {
                val ay = a.pose.ty()
                if (kotlin.math.abs(ay - expected) <= band) return ay
            }
        }

        var best: Float? = null
        var bestDelta = Float.MAX_VALUE
        for (plane in planes) {
            if (plane.trackingState == TrackingState.TRACKING &&
                plane.subsumedBy == null &&
                plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING
            ) {
                val py = plane.centerPose.ty()
                val delta = kotlin.math.abs(py - expected)
                if (delta <= band && delta < bestDelta) {
                    best = py
                    bestDelta = delta
                }
            }
        }
        return best ?: expected
    }

    /**
     * Anchors to the ground where the road is (lower-centre of the view). Placed
     * once and re-placed if the anchor stops tracking, giving a stable ground
     * reference so the path stays locked to the road.
     */
    private fun maybePlaceAnchor(frame: Frame) {
        val existing = anchor
        if (existing != null && existing.trackingState == TrackingState.TRACKING) return
        if (viewportWidth == 0 || viewportHeight == 0) return
        val cx = viewportWidth / 2f
        val cy = viewportHeight * 0.68f
        for (hit in frame.hitTest(cx, cy)) {
            val trackable = hit.trackable
            if (trackable is Plane &&
                trackable.trackingState == TrackingState.TRACKING &&
                trackable.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                trackable.isPoseInPolygon(hit.hitPose)
            ) {
                existing?.detach()
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

        /** Assumed height of the phone camera above the ground while walking. */
        private const val EYE_HEIGHT = 1.4f
    }
}

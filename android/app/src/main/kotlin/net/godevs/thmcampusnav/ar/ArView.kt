package net.godevs.thmcampusnav.ar

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import net.godevs.thmcampusnav.ar.helpers.DisplayRotationHelper
import net.godevs.thmcampusnav.ar.rendering.BackgroundRenderer
import net.godevs.thmcampusnav.ar.rendering.MarkerRenderer
import net.godevs.thmcampusnav.ar.rendering.PlaneRenderer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * A Flutter [PlatformView] that hosts a live ARCore session with horizontal
 * plane detection, rendering the camera feed, detected planes and a
 * world-anchored marker via OpenGL ES. Tracking status is streamed back to
 * Flutter over a per-view method channel.
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

    private var session: Session? = null
    private var glInitialised = false
    private var viewportWidth = 0
    private var viewportHeight = 0

    private var anchor: Anchor? = null

    private val viewMatrix = FloatArray(16)
    private val projMatrix = FloatArray(16)
    private val anchorMatrix = FloatArray(16)

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
                camera.getProjectionMatrix(projMatrix, 0, 0.1f, 100f)

                val planes = session.getAllTrackables(Plane::class.java)
                planeRenderer.draw(planes, viewMatrix, projMatrix)

                if (anchor == null) tryPlaceAnchor(frame)
                anchor?.let { a ->
                    if (a.trackingState == TrackingState.TRACKING) {
                        a.pose.toMatrix(anchorMatrix, 0)
                        markerRenderer.draw(anchorMatrix, viewMatrix, projMatrix)
                    }
                }

                reportStatus("tracking", countActivePlanes(planes))
            } else {
                reportStatus("paused", 0)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Exception on the GL thread", t)
        }
    }
    // endregion

    private fun tryPlaceAnchor(frame: com.google.ar.core.Frame) {
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

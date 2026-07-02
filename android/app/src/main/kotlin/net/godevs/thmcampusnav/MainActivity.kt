package net.godevs.thmcampusnav

import com.google.ar.core.ArCoreApk
import com.google.ar.core.ArCoreApk.Availability
import com.google.ar.core.ArCoreApk.InstallStatus
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import net.godevs.thmcampusnav.ar.ArViewFactory

class MainActivity : FlutterActivity() {

    private var userRequestedInstall = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Register the native ARCore platform view.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            AR_VIEW_TYPE,
            ArViewFactory(this, messenger, AR_CHANNEL),
        )

        // ARCore availability + install requests.
        MethodChannel(messenger, AR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAvailability" -> result.success(checkAvailability())
                "requestInstall" -> result.success(requestInstall())
                else -> result.notImplemented()
            }
        }
    }

    private fun checkAvailability(): String {
        val availability = ArCoreApk.getInstance().checkAvailability(this)
        return when (availability) {
            Availability.SUPPORTED_INSTALLED -> "ready"
            Availability.SUPPORTED_APK_TOO_OLD,
            Availability.SUPPORTED_NOT_INSTALLED -> "needsInstall"
            Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> "unsupported"
            else -> "unknown"
        }
    }

    private fun requestInstall(): Boolean {
        return try {
            when (ArCoreApk.getInstance().requestInstall(this, !userRequestedInstall)) {
                InstallStatus.INSTALLED -> true
                InstallStatus.INSTALL_REQUESTED -> {
                    userRequestedInstall = true
                    false
                }
                else -> false
            }
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val AR_VIEW_TYPE = "net.godevs.thmcampusnav/ar_view"
        private const val AR_CHANNEL = "net.godevs.thmcampusnav/ar"
    }
}

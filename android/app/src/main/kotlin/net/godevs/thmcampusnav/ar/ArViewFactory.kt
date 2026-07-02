package net.godevs.thmcampusnav.ar

import android.content.Context
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Creates [ArView] instances for Flutter's hybrid-composition platform views. */
class ArViewFactory(
    private val lifecycleOwner: LifecycleOwner,
    private val messenger: BinaryMessenger,
    private val channelBase: String,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return ArView(context, lifecycleOwner, messenger, viewId, channelBase)
    }
}

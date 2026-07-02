# Keep ARCore classes (the SDK relies on native/reflection access).
-keep class com.google.ar.core.** { *; }
-keep class com.google.ar.sceneform.** { *; }
-dontwarn com.google.ar.core.**

# Keep the app's native platform-view / channel entry points.
-keep class net.godevs.thmcampusnav.** { *; }

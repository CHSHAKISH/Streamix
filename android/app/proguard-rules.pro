# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Camera Plugin
-keep class io.flutter.plugins.camera.** { *; }
-keep class androidx.camera.** { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-keepattributes *Annotation*
-dontwarn org.webrtc.**

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Video Player
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**


# Firebase (you're using it)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Supabase/OkHttp/Network (CRITICAL for release builds)
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Keep Supabase classes
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# HTTP Client (CRITICAL for image loading)
-keep class java.net.** { *; }
-keep class javax.net.** { *; }
-keep class org.apache.http.** { *; }
-dontwarn org.apache.http.**
-dontwarn java.net.**

# Image Loading and Caching
-keep class com.bumptech.glide.** { *; }
-keep class androidx.core.graphics.** { *; }
-keep class android.graphics.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep HTTP response classes
-keepclassmembers class * extends java.net.URLConnection {
    protected java.net.URL url;
    protected java.net.Proxy proxy;
}

# Prevent stripping SSL/TLS classes
-keep class javax.net.ssl.** { *; }
-keep class org.conscrypt.** { *; }
-dontwarn org.conscrypt.**
-keep class sun.security.ssl.** { *; }
-dontwarn sun.security.ssl.**

# Prevent obfuscation of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep custom model classes (Firestore)
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
}



# Keep WebRTC classes
-keep class org.webrtc.** { *; }

# Keep JNI native methods
-keepclassmembers class * {
    native <methods>;
}

# Prevent stripping codecs
-keep class org.webrtc.audio.** { *; }
-keep class org.webrtc.video.** { *; }

# Prevent stripping peer connection
-keep class org.webrtc.PeerConnectionFactory { *; }
-keep class org.webrtc.PeerConnection { *; }

# Prevent removing utility classes
-keep class org.webrtc.Logging { *; }
-keep class org.webrtc.Camera2Capturer { *; }

# Flutter required rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.embedding.** { *; }

# Prevent stripping Kotlin (important for release crash)
-keep class kotlin.** { *; }
-dontwarn kotlin.**


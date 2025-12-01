plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.streamix"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // 1. Set Java 8 (Required)
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8

        // 2. Enable Desugaring (Required for Notifications)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.streamix"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 3. Add Desugar Library
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Fix for Flutter not finding APK with Kotlin DSL
afterEvaluate {
    tasks.register("copyFlutterApk") {
        doLast {
            val flutterApkDir = file("${project.rootDir}/../build/app/outputs/flutter-apk")
            flutterApkDir.mkdirs()
            
            val androidApkDir = file("${layout.buildDirectory.get()}/outputs/flutter-apk")
            if (androidApkDir.exists()) {
                copy {
                    from(androidApkDir)
                    into(flutterApkDir)
                    include("*.apk")
                }
                println("✅ APK copied to Flutter expected location")
            }
        }
    }

    tasks.findByName("assembleRelease")?.finalizedBy("copyFlutterApk")
    tasks.findByName("assembleDebug")?.finalizedBy("copyFlutterApk")
}

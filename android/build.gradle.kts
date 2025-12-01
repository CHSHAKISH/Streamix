allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Removed custom build directory configuration to fix camera plugin compatibility
// This was causing "different roots" errors with camera_android_camerax plugin

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

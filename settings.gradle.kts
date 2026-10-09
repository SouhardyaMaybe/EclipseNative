pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

rootProject.name = "EclipseNative"

include(":lwjgl3-android", ":openal-android")

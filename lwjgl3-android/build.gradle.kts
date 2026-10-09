// Packages the LWJGL3 Android natives (per-ABI .so files produced by
// scripts/build-lwjgl3-android.sh and placed into src/main/jniLibs/ by CI)
// into lwjgl3-natives-release.aar.
//
// DRAFT: pure-jni Android library; no Java/Kotlin code, empty classes.jar.

plugins { id("com.android.library") }

base { archivesName.set("lwjgl3-natives") }

android {
    namespace = "me.eclipse.launcher.natives.lwjgl3"
    compileSdk = 34
    ndkVersion = "25.2.9519653"

    defaultConfig { minSdk = 21 }

    sourceSets["main"].jniLibs.srcDir("src/main/jniLibs")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

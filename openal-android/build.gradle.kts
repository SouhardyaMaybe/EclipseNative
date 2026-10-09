// Packages the OpenAL Soft Android native (libopenal.so per ABI, produced by
// scripts/build-openal-android.sh and placed into src/main/jniLibs/ by CI)
// into openal-soft-release.aar.
//
// DRAFT: pure-jni Android library; no Java/Kotlin code, empty classes.jar.

plugins { id("com.android.library") }

base { archivesName.set("openal-soft") }

android {
    namespace = "me.eclipse.launcher.natives.openal"
    compileSdk = 34
    ndkVersion = "25.2.9519653"

    defaultConfig { minSdk = 21 }

    sourceSets["main"].jniLibs.srcDir("src/main/jniLibs")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

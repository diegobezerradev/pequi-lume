// Lume for Android: a NativeActivity app with no Java or Kotlin code.
// Zig builds the native library and the asset packs (`zig build android` in
// the repository root); Gradle only packages them.
//
// Debug:   ./gradlew assembleDebug    (APK, debug key, Zig ReleaseSafe)
// Release: ./gradlew bundleRelease    (AAB for Google Play, Zig ReleaseFast)
//
// Release signing takes the upload key from `android/keystore.properties`
// (never committed; see keystore.properties.example) or from the
// PEQUI_KEYSTORE_FILE, PEQUI_KEYSTORE_PASSWORD, PEQUI_KEY_ALIAS and
// PEQUI_KEY_PASSWORD environment variables (CI secrets). Without a key the
// release is signed with the debug key, which Google Play refuses.

import java.util.Properties

plugins {
    id("com.android.application")
}

val repoRoot: File = rootDir.parentFile
val zigOut: File = repoRoot.resolve("zig-out/android")

// The version lives in build.zig.zon (one place for Windows and Android).
val zon = repoRoot.resolve("build.zig.zon").readText()
val gameVersion: String = Regex("\\.version\\s*=\\s*\"([^\"]+)\"").find(zon)?.groupValues?.get(1) ?: "0.0.0"
// Google Play needs a bigger versionCode for every upload: CI passes its run
// number; otherwise it comes from the version (1.2.3 -> 10203).
val gameVersionCode: Int = System.getenv("PEQUI_VERSION_CODE")?.toIntOrNull() ?: run {
    val parts = gameVersion.split(".").map { it.toIntOrNull() ?: 0 } + listOf(0, 0, 0)
    maxOf(1, parts[0] * 10000 + parts[1] * 100 + parts[2])
}

val keystoreProperties = Properties().apply {
    val file = rootDir.resolve("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun signingValue(property: String, environment: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(environment)
val keystorePath = signingValue("storeFile", "PEQUI_KEYSTORE_FILE")
val hasReleaseKey = keystorePath != null && rootDir.resolve(keystorePath).exists()

android {
    namespace = "io.github.diegobezerradev.lume"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.diegobezerradev.lume"
        minSdk = 26 // AAudio
        targetSdk = 35
        versionCode = gameVersionCode
        versionName = gameVersion
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootDir.resolve(keystorePath!!)
                storePassword = signingValue("storePassword", "PEQUI_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "PEQUI_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "PEQUI_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("lume: no upload key (android/keystore.properties or PEQUI_KEYSTORE_*): the release is signed with the debug key, which Google Play refuses.")
                signingConfigs.getByName("debug")
            }
        }
    }

    // Asset packs are read at offsets: stored uncompressed in the APK, a read
    // is a plain seek; compressed, every seek would inflate from the start.
    androidResources {
        noCompress.add("pqa")
    }

    sourceSets["main"].apply {
        jniLibs.srcDir(zigOut.resolve("lib"))
        assets.srcDir(zigOut.resolve("assets"))
    }
}

// Release builds get Zig's ReleaseFast (no safety checks, no debug overlay);
// everything else ReleaseSafe (checks on, overlay on three fingers).
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release") }

val zigBuild by tasks.registering(Exec::class) {
    description = "Builds liblume.so (arm64-v8a, x86_64) and the asset packs with Zig."
    workingDir = repoRoot
    commandLine("zig", "build", "android", "-Doptimize=" + if (releaseRequested) "ReleaseFast" else "ReleaseSafe")
}

tasks.named("preBuild") {
    dependsOn(zigBuild)
}

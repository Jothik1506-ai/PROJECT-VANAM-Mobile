import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // NOTE: `kotlin-android` is deliberately NOT declared here.
    //
    // This app uses AGP 9 built-in Kotlin (android.builtInKotlin=true in
    // gradle.properties), per Flutter's "Migrate to built-in Kotlin" guide.
    // AGP compiles Kotlin itself, so neither this module nor any plugin applies
    // the Kotlin Gradle Plugin. That requires every Flutter plugin we depend on
    // to support built-in Kotlin (firebase_core >=4.14, firebase_crashlytics,
    // mobile_scanner >=7.4.1, package_info_plus >=10.2.0, share_plus >=13.2.0);
    // do not downgrade them below those versions.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    // Required for firebase_crashlytics to fully initialize/report on
    // Android (build-id injection + mapping file upload) — same
    // conditional pattern as google-services above, since both depend on
    // this file existing (it doesn't in a plain checkout without Firebase
    // configured).
    apply(plugin = "com.google.firebase.crashlytics")
}

// Release signing config, loaded from android/key.properties (gitignored).
// See docs/OTA-RELEASES.md section 2 — this key must stay identical for the
// life of the app. Android only installs an update signed by the same key,
// and losing it forces every family member to uninstall (destroying their
// locally-stored E2EE private keys) before they can update again.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.containsKey("storeFile")
val buildingRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

android {
    namespace = "in.aivafreelancia.vanam.vanam_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "in.aivafreelancia.vanam.vanam_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("ota") {
            dimension = "distribution"
            // Makes `ota` the variant Android Studio / the AGP tooling selects
            // by default. See the `flutter-apk` alias tasks below for why a
            // default alone isn't enough to make a bare `flutter run` work.
            isDefault = true
        }
        create("play") {
            dimension = "distribution"
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (buildingRelease) {
                throw GradleException(
                    "Release signing key missing. Create android/key.properties " +
                        "with the stable VANAM release keystore before building a release APK."
                )
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // If key.properties is absent we deliberately fail the release
            // build rather than falling back to the debug key or emitting an
            // unsigned APK.
            // A debug-signed build that reaches a real phone can never be
            // updated by a properly-signed one — the user would have to
            // uninstall first. Failing loudly here is the safer outcome.
        }
    }
}

// NOTE on AAB size: BUNDLE-METADATA/.../*.so.sym (~57MB across ABIs) and
// the ProGuard mapping file (~45MB) dominate the raw .aab on disk. Tried
// android.buildTypes.release.ndk.debugSymbolLevel at "symbol_table" via three
// different mechanisms (plain DSL, project.afterEvaluate,
// androidComponents.finalizeDsl) — all three produced a byte-identical AAB to
// the "full" (default) setting. Conclusion: Flutter's release engine/app
// binaries don't carry more than symbol-table-level info to begin with, so
// there's nothing for a lower level to trim here; this isn't reducible
// through this knob. "none" does shrink it, but Flutter's own build tool
// hard-requires this metadata to exist as proof AGP stripped debug info from
// the shipped .so files (_isAabStrippedOfDebugSymbols in
// flutter_tools/lib/src/android/gradle.dart) and refuses to produce the
// bundle without it. None of this metadata reaches a user's phone anyway —
// Play strips BUNDLE-METADATA before generating installable per-device
// splits — so it's not worth fighting further.

// Kotlin must target the same JVM as compileOptions above, or Gradle fails with
// "Inconsistent JVM-target compatibility".
//
// Kotlin 2.3.20 removed the old `android { kotlinOptions { jvmTarget } }` DSL
// (it is now a compile ERROR, not a warning); built-in Kotlin exposes the
// `kotlin { compilerOptions { } }` block instead.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// The `play` flavor only ever ships as a signed release App Bundle
// (tool/play-release.ps1). Nothing consumes a play debug or profile build, yet
// a flavorless `assembleDebug` built one anyway — a second full ~214 MB APK per
// run, roughly doubling the build time of every bare `flutter run`.
androidComponents {
    beforeVariants(selector().withFlavor("distribution" to "play")) { variantBuilder ->
        if (variantBuilder.buildType != "release") {
            variantBuilder.enable = false
        }
    }
}

// Make a bare `flutter run` / `flutter build apk` work.
//
// Without `--flavor`, the Flutter tool asks Gradle for `assembleDebug` and then
// looks for `build/app/outputs/flutter-apk/app-debug.apk` — an UN-flavored
// filename (see _apkFilesFor in flutter_tools/lib/src/android/gradle.dart).
// Once product flavors exist, Flutter's Gradle plugin only ever writes flavored
// names (`app-ota-debug.apk`), so the bare command compiles everything
// successfully and then dies with "Gradle build failed to produce an .apk file".
// Setting isDefault on the flavor above does not help: that only steers the IDE
// variant picker, not the filename the tool greps for.
//
// `ota` is this app's real distribution channel (the `play` flavor exists only
// for tool/play-release.ps1), so alias each ota APK to the un-flavored name.
// This is purely additive — the flavored file stays exactly where
// tool/release.ps1 expects it, and explicit `--flavor` builds are unaffected.
//
// Deliberately NOT done for app bundles. A bare `flutter build appbundle`
// should keep failing loudly rather than quietly hand over an OTA-configured
// artifact to upload to Play (updater enabled, REQUEST_INSTALL_PACKAGES
// granted). Play builds go through tool/play-release.ps1, which is explicit.
val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk")
listOf("debug", "profile", "release").forEach { mode ->
    val modeSuffix = mode.replaceFirstChar { it.uppercase() }
    val aliasTask = tasks.register("copyOta${modeSuffix}ApkToDefaultName") {
        description = "Aliases app-ota-$mode.apk to app-$mode.apk so a flavorless flutter run finds it."
        doLast {
            val dir = flutterApkDir.get().asFile
            val flavored = dir.resolve("app-ota-$mode.apk")
            val alias = dir.resolve("app-$mode.apk")
            if (flavored.isFile) {
                flavored.copyTo(alias, overwrite = true)
            } else {
                // Never leave a stale alias behind — a `flutter run` that
                // silently installs the previous build is the exact failure
                // mode this project already got bitten by.
                alias.delete()
            }
        }
    }
    tasks.matching { it.name == "assembleOta$modeSuffix" }.configureEach {
        finalizedBy(aliasTask)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

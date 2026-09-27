pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Keep this at 9.0.1 or higher. Flutter's warnAGPVersion is 9.0.1, and the
    // app relies on AGP 9 built-in Kotlin (android.builtInKotlin=true, see
    // android/app/build.gradle.kts), which does not exist on AGP 8.x.
    id("com.android.application") version "9.0.1" apply false
    // Not applied to any module (built-in Kotlin compiles Kotlin); declared so
    // the Kotlin compiler version on the build classpath is 2.3.20.
    // Flutter warns below 2.3.20 and hard-errors below 2.2.20
    // (DependencyVersionChecker.warnKGPVersion / errorKGPVersion).
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("com.google.gms.google-services") version "4.4.4" apply false
    id("com.google.firebase.crashlytics") version "3.0.6" apply false
}

include(":app")

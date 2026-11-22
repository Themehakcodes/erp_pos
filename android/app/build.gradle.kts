plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mart20.pos"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mart20.pos.v2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        val buildDir = project.layout.buildDirectory.asFile.get()
        val vName = flutter.versionName ?: "1.0.2"
        val vCode = flutter.versionCode ?: 4
        val apkNames = listOf(
            "20MartPOS-v${vName}-b${vCode}-release.apk",
            "20MartPOS-v${vName}+${vCode}-release.apk"
        )

        val gradleReleaseApk = File(buildDir, "outputs/apk/release/app-release.apk")
        if (gradleReleaseApk.exists()) {
            val flutterApkDir = File(buildDir, "outputs/flutter-apk")
            flutterApkDir.mkdirs()

            println("\n========================================================")
            println("MDM RELEASE APKS GENERATED (Version: $vName, Build: $vCode):")
            apkNames.forEach { name ->
                val destGradle = File(gradleReleaseApk.parentFile, name)
                gradleReleaseApk.copyTo(destGradle, overwrite = true)
                val destFlutter = File(flutterApkDir, name)
                gradleReleaseApk.copyTo(destFlutter, overwrite = true)
                println("-> ${destFlutter.absolutePath}")
            }
            println("========================================================\n")
        }
    }
}

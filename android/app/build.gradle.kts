plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ibirapay.wallet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ibirapay.wallet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // F-Droid builds ONE arm64 APK (versionCode stays 100, no ABI split) with
        //   flutter build apk --target-platform android-arm64 --android-project-arg=disable-abi-filtering=true
        // and then only arm64-v8a is packaged, so the plugin AARs' stray armeabi-v7a/x86_64 libs (no Flutter engine next
        // to them, a 32-bit phone would install and crash) stay out. The flag is needed because the Flutter Gradle plugin
        // otherwise resets abiFilters to its own default list after this file is evaluated.
        // Any other build (tool/build-apk.sh: android-arm,android-arm64, no flag) gets exactly what it got before.
        val arm64Only = project.findProperty("target-platform") == "android-arm64"
        ndk { abiFilters += if (arm64Only) listOf("arm64-v8a") else listOf("armeabi-v7a", "arm64-v8a") }
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Shrink + obfuscate the Kotlin/Java side (the Dart side is obfuscated separately, by
            // `flutter build apk --obfuscate` in tool/build-apk.sh). Every plugin here (flutter_secure_storage,
            // the Spark SDK bridge, path_provider...) ships its own consumer-rules.pro, so R8 keeps what each needs.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

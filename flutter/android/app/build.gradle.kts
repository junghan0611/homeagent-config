plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.homeagent.homeagent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    // CHIP SDK AAR from libs/
    repositories {
        flatDir { dirs("libs") }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.homeagent.app"
        // Android 15 (API 35) 타겟. compileSdk 36은 빌드 도구, targetSdk가 호환성 결정
        minSdk = 26              // Android 8.0+ (Matter 기기 대부분)
        targetSdk = 35           // Android 15 (VanillaIceCream)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // CHIP SDK Android AAR — built from connectedhomeip chip-library
    // Place chip-library-debug.aar in app/libs/
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}

flutter {
    source = "../.."
}

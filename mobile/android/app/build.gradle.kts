plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.santim.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.santim.mobile"
        // EncryptedSharedPreferences needs 23; every SMS API we use is older.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
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

flutter {
    source = "../.."
}

dependencies {
    // Retry-with-backoff uploads that survive the app being swiped away. The
    // SMS receiver gets ~10 seconds before Android can kill the process, which
    // is nowhere near enough to trust a network call, so it only ever enqueues.
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // The device token is a long-lived bearer credential for a finance account;
    // it does not sit in plaintext prefs.
    implementation("androidx.security:security-crypto:1.0.0")
}

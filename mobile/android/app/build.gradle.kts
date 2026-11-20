plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystore = providers.environmentVariable("TAPMYPC_ANDROID_KEYSTORE")

android {
    namespace = "dev.tapmypc.tapmypc_mobile"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.tapmypc.tapmypc_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystore.isPresent) {
            create("tapmypcRelease") {
                storeFile = file(releaseKeystore.get())
                storePassword = providers.environmentVariable("TAPMYPC_ANDROID_STORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("TAPMYPC_ANDROID_KEY_ALIAS").get()
                keyPassword = providers.environmentVariable("TAPMYPC_ANDROID_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        release {
            val signing = if (releaseKeystore.isPresent) "tapmypcRelease" else "debug"
            signingConfig = signingConfigs.getByName(signing)
        }
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.14.0")
}

flutter {
    source = "../.."
}

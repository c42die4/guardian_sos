plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.cyberwarriors.guardian_sos"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.cyberwarriors.guardian_sos"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    debugImplementation("io.flutter:flutter_embedding_debug:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12")
    releaseImplementation("io.flutter:flutter_embedding_release:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12")
    profileImplementation("io.flutter:flutter_embedding_profile:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12")
}
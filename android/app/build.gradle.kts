import java.util.Properties
import java.io.FileInputStream

// Load key.properties
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.cyberwarriors.guardian_sos"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
            storeFile = keyProperties["storeFile"]?.let { file(it) }
            storePassword = keyProperties["storePassword"] as String
        }
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
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    flavorDimensions += "company"
    productFlavors {
        create("default") {
            dimension = "company"
            applicationId = "com.cyberwarriors.guardian_sos"
            resValue("string", "app_name", "Guardian SOS")
        }
        create("sos_security") {
            dimension = "company"
            applicationId = "com.cyberwarriors.sos_security"
            resValue("string", "app_name", "SOS Security")
        }
        create("highway_devils") {
            dimension = "company"
            applicationId = "com.highwaydevils.emergency"
            resValue("string", "app_name", "Highway Devils")
        }
        create("adventure") {
            dimension = "company"
            applicationId = "com.cyberwarriors.adventure_sos"
            resValue("string", "app_name", "Adventure SOS")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.multidex:multidex:2.0.1")
    debugImplementation("io.flutter:flutter_embedding_debug:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12")
    releaseImplementation("io.flutter:flutter_embedding_release:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12")
    profileImplementation("io.flutter:flutter_embedding_profile:1.0.0-052f31d115eceda8cbff1b3481fcde4330c4ae12")
}
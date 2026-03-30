pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val propertiesFile = settingsDir.resolve("local.properties")
        require(propertiesFile.exists()) {
            "local.properties file not found at ${propertiesFile.absolutePath}"
        }
        propertiesFile.reader().use { properties.load(it) }
        val sdk = properties.getProperty("flutter.sdk")
        require(!sdk.isNullOrBlank()) {
            "flutter.sdk not set in local.properties"
        }
        sdk
    }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
}

plugins {
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// Include Flutter plugins as subprojects
val flutterProjectRoot = rootProject.projectDir.parentFile.toPath()
val pluginsFile = flutterProjectRoot.resolve(".flutter-plugins-dependencies").toFile()

if (pluginsFile.exists()) {
    val pluginsJson = groovy.json.JsonSlurper().parse(pluginsFile) as Map<*, *>
    val plugins = pluginsJson["plugins"] as? Map<*, *>
    val androidPlugins = plugins?.get("android") as? List<*>

    androidPlugins?.forEach { plugin ->
        val pluginMap = plugin as? Map<*, *> ?: return@forEach
        val name = pluginMap["name"] as? String ?: return@forEach
        val path = pluginMap["path"] as? String ?: return@forEach
        val nativeBuild = pluginMap["native_build"] as? Boolean ?: true

        if (nativeBuild) {
            val pluginProject = File(path, "android")
            if (pluginProject.exists()) {
                include(":$name")
                project(":$name").projectDir = pluginProject
            }
        }
    }
}

include(":app")
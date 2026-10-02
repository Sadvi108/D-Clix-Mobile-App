import java.io.FileInputStream
import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties holds the upload keystore location and passwords. CI writes
// it from repository secrets; see docs/android-signing.md. It is git-ignored.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// onesignal:managed v1 — match Flutter's public app ID before a saved SDK can start.
val dartDefines = providers.gradleProperty("dart-defines").orNull
    ?.split(",")
    ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    ?.associate {
        val entry = it.split("=", limit = 2)
        entry[0] to entry.getOrElse(1) { "" }
    }
    ?: emptyMap()
val oneSignalAppId = dartDefines["ONESIGNAL_APP_ID"]
    ?: "effd15e0-373e-4981-b319-ea22407d2a56"
require(oneSignalAppId.isEmpty() ||
    oneSignalAppId.matches(Regex("[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"))) {
    "ONESIGNAL_APP_ID must be a UUID or empty."
}

android {
    namespace = "com.dclix.clubapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        // flutter_local_notifications schedules against java.time, which needs the
        // desugared JDK library to exist on the minSdk 24 devices we still support.
        // Without this the build fails at :app:checkReleaseAarMetadata.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.dclix.clubapp"
        buildConfigField("String", "ONESIGNAL_APP_ID", "\"$oneSignalAppId\"")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties (local runs, pull requests) release builds fall back
            // to the debug keystore. Release tags refuse to publish that; see the workflow.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Match onesignal_flutter 5.5.2's native dependency for early initialization.
    implementation("com.onesignal:OneSignal:5.8.0") // onesignal:managed v1
}

flutter {
    source = "../.."
}

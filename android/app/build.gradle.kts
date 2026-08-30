plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val releaseSigningValues =
    mapOf(
        "ANDROID_KEYSTORE_PATH" to System.getenv("ANDROID_KEYSTORE_PATH").orEmpty(),
        "ANDROID_KEYSTORE_ALIAS" to System.getenv("ANDROID_KEYSTORE_ALIAS").orEmpty(),
        "ANDROID_KEYSTORE_PASSWORD" to System.getenv("ANDROID_KEYSTORE_PASSWORD").orEmpty(),
        "ANDROID_KEY_PASSWORD" to System.getenv("ANDROID_KEY_PASSWORD").orEmpty(),
    )
val configuredSigningValues = releaseSigningValues.count { it.value.isNotBlank() }
val releaseBuildRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (configuredSigningValues in 1 until releaseSigningValues.size) {
    val missing = releaseSigningValues.filterValues { it.isBlank() }.keys.joinToString()
    throw GradleException("Android release signing is incomplete; missing: $missing")
}
if (releaseBuildRequested && configuredSigningValues == 0) {
    throw GradleException(
        "Android release signing is not configured. Run `just deploy-android-signing-setup`.",
    )
}
if (releaseBuildRequested) {
    val keystore = file(releaseSigningValues.getValue("ANDROID_KEYSTORE_PATH"))
    if (!keystore.isFile) {
        throw GradleException("Android release keystore does not exist: $keystore")
    }
}

android {
    namespace = "com.example.garbanzo_ai"
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
        applicationId = "com.example.garbanzo_ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (configuredSigningValues == releaseSigningValues.size) {
                storeFile = file(releaseSigningValues.getValue("ANDROID_KEYSTORE_PATH"))
                storePassword = releaseSigningValues.getValue("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseSigningValues.getValue("ANDROID_KEYSTORE_ALIAS")
                keyPassword = releaseSigningValues.getValue("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

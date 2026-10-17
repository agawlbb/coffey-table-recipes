import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FirebaseInitProvider needs native options on a cold push launch, before Dart.
// Reuse the release's existing dart defines; no local Firebase file is tracked.
val firebaseDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(",").filter { it.isNotEmpty() }.mapNotNull {
        val pair = String(Base64.getDecoder().decode(it), Charsets.UTF_8).split("=", limit = 2)
        if (pair.size == 2) pair[0] to pair[1] else null
    }.toMap()

android {
    namespace = "com.coffeytable.coffey_table_recipes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.coffeytable.coffey_table_recipes"
        mapOf("google_app_id" to "FIREBASE_ANDROID_APP_ID", "google_api_key" to "FIREBASE_ANDROID_API_KEY",
            "gcm_defaultSenderId" to "FIREBASE_SENDER_ID", "project_id" to "FIREBASE_PROJECT_ID").forEach { (resource, define) ->
            firebaseDefines[define]?.takeIf { it.isNotEmpty() }?.let { resValue("string", resource, it) }
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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

// Keep aligned with the locked firebase_core Android SDK BOM.
dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.19.0"))
    implementation("com.google.firebase:firebase-messaging")
}

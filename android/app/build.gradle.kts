plugins {
    id("com.android.application")
    // Required for the home-screen widgets (SingleNoteWidget/ReminderListWidget),
    // which are built with Jetpack Glance's Compose-based DSL - version must
    // match the Kotlin version pinned in settings.gradle.kts.
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jayemar.jotes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jayemar.jotes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        compose = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // For the home-screen widgets - see the plugins block above.
    implementation("androidx.glance:glance-appwidget:1.1.1")
    // For BootRestoreWorker/BootRestoreReceiver - see their own doc
    // comments for why a WorkManager Worker, not a foreground Service, is
    // what actually runs reliably when triggered from BOOT_COMPLETED on
    // Android 14+. Declared explicitly rather than relying on this
    // already being a transitive dependency of another plugin.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}

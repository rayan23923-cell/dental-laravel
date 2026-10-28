import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (2026-09-02, for the Google Play internal-testing
// upload) — reads from `android/key.properties`, never committed
// (already covered by android/.gitignore's `key.properties`/`*.jks`/
// `*.keystore` entries) so the actual keystore password never touches
// version control or CI logs. Deliberately optional: a build with no
// `key.properties` present still succeeds — see the release
// signingConfig below, which falls back to the debug key exactly like
// this file did before, so a plain local `flutter run --release` for
// day-to-day dev work is unaffected. Only a build that explicitly needs
// to be uploadable to Play Console (Codemagic's release workflow) needs
// this file to actually exist.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Firebase (push notifications) — only applied once a real
// google-services.json exists (see flutter_app/README.md's Firebase
// section). Until then this silently no-ops and the build is completely
// unaffected — do not remove this guard, an unconditional `apply` here
// would break every build the moment this file is missing (which is the
// current state).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Google Play build (2026-10-28): `flutter build appbundle
// --dart-define=STORE_BUILD=true --android-project-arg=storeBuild=true`
// merges src/store/AndroidManifest.xml, which drops the in-app updater's
// install permission. The /download and offline APKs keep it.
val storeBuild = (project.findProperty("storeBuild") as String?) == "true"

android {
    namespace = "com.dentalclinic.dental_clinic_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // AIDL codegen is off by default in modern AGP — needed for
    // PosPrinterPlugin.kt's `IPosPrinterService.aidl` to actually get
    // compiled into a usable Stub class.
    buildFeatures {
        aidl = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dentalclinic.dental_clinic_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    if (storeBuild) {
        sourceSets.getByName("release").manifest.srcFile("src/store/AndroidManifest.xml")
    }

    buildTypes {
        release {
            // Real release signing once android/key.properties exists
            // (see its own doc comment above) — falls back to the debug
            // key otherwise, unchanged from before, so this never blocks
            // a plain local release build.
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider for in-app updates (AppUpdatePlugin.kt).
    implementation("androidx.core:core:1.13.1")
}

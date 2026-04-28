import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.torrentspire.ai"
    // Use a fixed SDK to ensure proper native library loading on newer Android versions
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.torrentspire.ai"
        manifestPlaceholders["appLabel"] = "Convert the Spire Reborn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Minimum supported SDK required by bundled Android plugins.
        minSdk = 24
        // Target API 35 to satisfy Play Console requirements
        targetSdk = 35
        versionCode = 1053
        versionName = "10.5.3"
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    splits {
        abi {
            isEnable = false
        }
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("full") {
            dimension = "distribution"
            applicationIdSuffix = ".full"
            manifestPlaceholders["appLabel"] = "Convert the Spire Reborn Full"
        }
        create("play") {
            dimension = "distribution"
            manifestPlaceholders["appLabel"] = "Bitplayer"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
            pickFirsts += setOf("lib/**/libc++_shared.so")
        }
    }

    val storeFilePath = keystoreProperties["storeFile"]?.toString()?.trim().orEmpty()
    val storePassword = keystoreProperties["storePassword"]?.toString().orEmpty()
    val keyAlias = keystoreProperties["keyAlias"]?.toString().orEmpty()
    val keyPassword = keystoreProperties["keyPassword"]?.toString().orEmpty()
    val hasReleaseSigning =
        storeFilePath.isNotBlank() &&
        storePassword.isNotBlank() &&
        keyAlias.isNotBlank() &&
        keyPassword.isNotBlank()

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(storeFilePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    // NOTE: Flutter tooling can set ndk abiFilters (e.g. when using
    // `flutter build apk --split-per-abi`). Having a `splits { abi { ... } }`
    // block here leads to a conflict (ndk abiFilters cannot be present when
    // splits abi filters are set). We intentionally avoid configuring ABI
    // splits in Gradle and instead let Flutter handle ABI splitting when
    // requested via its build flags.

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Modern window insets and edge-to-edge support
    implementation("androidx.core:core:1.14.0")
    implementation("androidx.core:core-ktx:1.13.1")
    // Activity API for lifecycle and PiP support
    implementation("androidx.activity:activity-ktx:1.9.0")
}

// After APKs are produced by Gradle/Flutter, copy them to the workspace releases/android folder
tasks.register("copyApkToReleases") {
    doLast {
        // Flutter may emit APKs in the module build dir or the project root build dir.
        val moduleApkDir = file("${buildDir.absolutePath}/outputs/flutter-apk")
        val projectApkDir = file("${project.rootDir}/build/app/outputs/flutter-apk")
        val apkDir = when {
            moduleApkDir.exists() -> moduleApkDir
            projectApkDir.exists() -> projectApkDir
            else -> moduleApkDir
        }
        val destDir = file("${project.rootDir}/releases/android")
        if (!destDir.exists()) destDir.mkdirs()
        if (apkDir.exists()) {
            apkDir.listFiles()?.filter { it.extension == "apk" }?.forEach { apk ->
                copy {
                    from(apk)
                    into(destDir)
                }
            }
        }
    }
}

// Ensure the copy runs after assembling release APKs
// Attach the copy task to any assemble*Release task (accounts for variant names)
tasks.matching { task ->
    task.name.startsWith("assemble", ignoreCase = true) && task.name.contains("Release")
}.configureEach {
    finalizedBy("copyApkToReleases")
}

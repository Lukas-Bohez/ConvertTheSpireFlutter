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

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        load(FileInputStream(localPropertiesFile))
    }
}

val flutterVersionCode = (localProperties.getProperty("flutter.versionCode")
    ?.toIntOrNull() ?: 1)
val flutterVersionName = localProperties.getProperty("flutter.versionName")
    ?.trim()
    .orEmpty()
    .ifEmpty { "1.0" }

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
        manifestPlaceholders["appLabel"] = "BitPlayer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Minimum supported SDK required by bundled Android plugins.
        minSdk = 24
        // Target API 36 (Android 16) to satisfy Play Console requirements
        targetSdk = 36
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildFeatures {
        buildConfig = true
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
            // Installable alongside Play Store builds by using a different
            // applicationId suffix for GitHub/CI artifacts.
            applicationIdSuffix = ".github"
            versionNameSuffix = "-github"
            manifestPlaceholders["appLabel"] = "Convert The Spire Reborn"
        }
        create("play") {
            dimension = "distribution"
            // Play Store uses the canonical package name; no suffix.
            manifestPlaceholders["appLabel"] = "BitPlayer"
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
            // Enable shrinking + optimized resource reduction for smaller,
            // faster release builds.
            isMinifyEnabled = true
            isShrinkResources = true
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
    implementation("androidx.core:core:1.13.1")
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

// ---------------------------------------------------------------------------
// Strip dev-dependency plugin registrations from GeneratedPluginRegistrant
// before javac runs on a release build.
//
// `flutter pub get` writes a registrant that registers every plugin, including
// ones that are only dev_dependencies (integration_test). Gradle correctly
// leaves those AARs off the *release* compile classpath, so the generated Java
// then fails to compile with:
//     package dev.flutter.plugins.integration_test does not exist
//
// Flutter records which plugins are dev-only in .flutter-plugins-dependencies,
// so that file is the source of truth. Only release variants are touched, so
// debug builds keep integration_test and `flutter test integration_test/`
// still works.
// ---------------------------------------------------------------------------
val stripDevPluginsFromRegistrant by tasks.registering {
    doLast {
        val registrant =
            file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        val depsFile = file("${project.rootDir}/../.flutter-plugins-dependencies")
        if (!registrant.exists() || !depsFile.exists()) return@doLast

        // Names of plugins flagged as dev-only. Parsed with plain string
        // scanning rather than a regex: the entries are one-line JSON objects
        // and this avoids a dependency on a JSON library in the build script.
        // Flutter writes this file without spaces after the colons, but do
        // not depend on that: strip whitespace first so either form parses.
        val deps = depsFile.readText().filterNot { it.isWhitespace() }
        val devPluginNames = mutableListOf<String>()
        for (chunk in deps.split("{")) {
            if (!chunk.contains("\"dev_dependency\":true")) continue
            val key = "\"name\":\""
            val start = chunk.indexOf(key)
            if (start < 0) continue
            val from = start + key.length
            val end = chunk.indexOf("\"", from)
            if (end > from) devPluginNames.add(chunk.substring(from, end))
        }
        if (devPluginNames.isEmpty()) return@doLast

        // Each registration is a fixed five-line block:
        //     try {
        //       flutterEngine.getPlugins().add(new <class>());
        //     } catch (Exception e) {
        //       Log.e(TAG, "Error registering plugin <name>, <class>", e);
        //     }
        val lines = registrant.readLines()
        val drop = BooleanArray(lines.size)
        var removed = 0
        for (i in lines.indices) {
            val line = lines[i]
            if (!line.contains("getPlugins().add(")) continue
            if (devPluginNames.none { line.contains(".$it.") }) continue
            for (j in (i - 1)..(i + 3)) {
                if (j in lines.indices) drop[j] = true
            }
            removed++
        }
        if (removed == 0) return@doLast

        registrant.writeText(
            lines.filterIndexed { i, _ -> !drop[i] }.joinToString("\n") + "\n"
        )
        logger.lifecycle(
            "Removed $removed dev-dependency plugin registration(s) from " +
                "GeneratedPluginRegistrant for this release build."
        )
    }
}

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("ReleaseJavaWithJavac") }
    .configureEach { dependsOn(stripDevPluginsFromRegistrant) }

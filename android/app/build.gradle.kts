// android/app/build.gradle.kts
// Android build configuration with native C++ support via CMake

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.quran.accessibility"
    compileSdk = 34
    ndkVersion = "25.2.9519653"

    defaultConfig {
        applicationId = "com.quran.accessibility"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        // CMake native build configuration
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_TOOLCHAIN=clang",
                    "-DANDROID_STL=c++_shared"
                )
            }
        }

        // Multi-ABI support
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
    }

    // CMake build integration
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Sign with release key for production
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // AndroidX core
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    
    // Audio focus handling
    implementation("androidx.media:media:1.7.0")
}

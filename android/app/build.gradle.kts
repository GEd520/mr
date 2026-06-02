plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dan_shenqi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
        }
    }

    defaultConfig {
        applicationId = "com.example.dan_shenqi"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isShrinkResources = true
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // OkHttp - 高性能HTTP客户端，支持拦截器/缓存/WebSocket
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // OkHttp 拦截器（日志/缓存）
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    // Jsoup - HTML解析器，用于书源内容提取
    implementation("org.jsoup:jsoup:1.18.1")
    // Kotlin 协程（OkHttp异步支持）
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Rhino - JavaScript 引擎（Android 无 javax.script）
    implementation("org.mozilla:rhino:1.9.1")
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mr.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // 使用 compilerOptions DSL（kotlinOptions 已在 Kotlin 2.2+ 废弃）
    // 但 android kotlinOptions 仍在 android {} 块内可用，保留兼容
    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        applicationId = "com.mr.app"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 保险 #1：ndk.abiFilters 只编译 arm64-v8a 的 .so
        // minSdk=29 起 Android 设备基本都是 arm64，x86_64 只用于模拟器
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        // QuickJS NDK 编译配置
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_static",
                    // 传递项目根目录，CMakeLists.txt 用它定位 quickjs/ 源码
                    "-DPROJECT_ROOT_DIR=${rootProject.projectDir.parentFile?.absolutePath}"
                )
                cFlags += "-D_GNU_SOURCE"
                // 显式只编译 arm64-v8a（覆盖任何继承的 ABI 配置）
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    // 保险 #2：splits.abi 显式只保留 arm64-v8a，构建时只生成一个 APK
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a")
            isUniversalApk = false
        }
    }

    // 排除重复/冗余文件，减小 APK 体积
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/*.kotlin_module",
                "META-INF/INDEX.LIST",
                "META-INF/io.netty.versions.properties",
                "META-INF/versions/**",
                "kotlin/**",
                "kotlin-tooling-metadata.json",
                "DebugProbesKt.bin",
                "META-INF/proguard/**",
            )
        }
        // .so 文件不压缩（Android 6+ 直接 mmap，压缩反而浪费 CPU）
        jniLibs {
            useLegacyPackaging = false
            // 保险 #3：packaging 显式排除 x86_64 和 armeabi-v7a 的 .so
            // 即使上游依赖带了这些 ABI 的 .so 也会被剔除
            excludes += listOf(
                "lib/x86_64/**",
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/mips/**",
                "lib/mips64/**"
            )
        }
    }

    // QuickJS CMake 构建配置（编译 C 源码为 libquickjs_c_bridge.so）
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
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
    // Kotlin 标准库（显式声明版本，确保 Android Studio 能解析）
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.2.20")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // OkHttp（HTTP 客户端）
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    // Jsoup（HTML 解析 + 内置 XPath selectXpath()）
    implementation("org.jsoup:jsoup:1.22.2")
    // JsonPath（JSON 解析）
    implementation("com.jayway.jsonpath:json-path:2.9.0")
    // Commons Text（HTML 反转义）
    implementation("org.apache.commons:commons-text:1.12.0")
    // Java 8+ API 脱糖
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

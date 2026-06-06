buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // 显式声明 Kotlin 插件，确保 Android Studio 能解析 classpath
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // 统一所有子项目的 JVM target，避免 Java 与 Kotlin 编译目标不一致
    // 修复 flutter_plugin_android_lifecycle 等子项目的 JVM 兼容性冲突
    afterEvaluate {
        // 统一 Java 编译目标
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_21.toString()
            targetCompatibility = JavaVersion.VERSION_21.toString()
        }
        // 统一 Kotlin 编译目标（使用 compilerOptions DSL，kotlinOptions 已废弃）
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

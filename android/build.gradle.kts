// android/build.gradle.kts

buildscript {
    // KTS 變數定義，取代 Groovy 的 ext.
    val kotlin_version by extra("1.9.0") 

    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        // KTS 依賴使用 () 而非空格和單引號
        classpath("com.android.tools.build:gradle:7.3.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version")
        
        // Google Services
        classpath("com.google.gms:google-services:4.4.0")
    }
}

// -------------------------------------------------------------
// 以下是您專案中關於 build directory 的自定義設定，保留：

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
// -------------------------------------------------------------
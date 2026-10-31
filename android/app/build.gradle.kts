import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

val releaseStoreFile = file("keystore.jks")
val releaseStorePassword = localProperties.getProperty("storePassword")
val releaseKeyAlias = localProperties.getProperty("keyAlias")
val releaseKeyPassword = localProperties.getProperty("keyPassword")
val hasReleaseSigning = releaseStoreFile.exists() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

val verifyReleaseSigning by tasks.registering {
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException("Android release signing inputs are missing or incomplete")
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyReleaseSigning)
}

android {
    namespace = "com.follow.clash"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fengwo.accelerator"
        minSdk = flutter.minSdkVersion
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".dev"
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        getByName("test").java.setSrcDirs(listOf("../tests/app"))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":service"))
    implementation(project(":common"))
    implementation(project(":core"))
    implementation(libs.core.splashscreen)
    implementation(libs.gson)
    implementation(libs.smali.dexlib2) {
        exclude(group = "com.google.guava", module = "guava")
    }
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.crashlytics.ndk)
    implementation(libs.firebase.analytics)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

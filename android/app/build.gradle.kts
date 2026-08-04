plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.com.veredas.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.com.veredas.app"
        // O flutter_secure_storage 10.x exige minSdk >= 23 (guarda o código de
        // convite entre o signUp e a confirmação de e-mail).
        //
        // O PLANO.md §5 manda fixar `minSdk = 23`, mas o default do Flutter
        // 3.44 já é 24 — fixar 23 seria um DOWNGRADE, e o `flutter build`
        // reescreve este arquivo na migração do Gradle, revertendo o valor.
        // Delegar ao default satisfaz o requisito e não briga com a ferramenta.
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
        }
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

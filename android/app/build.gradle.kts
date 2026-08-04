import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Lê a configuração de assinatura de `android/key.properties` (gitignored).
// Sem o arquivo, o build de release usa as debug keys — suficiente para
// desenvolvimento, mas não para publicar na Play Store.
val keystoreProperties = Properties().apply {
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        load(FileInputStream(keystoreFile))
    }
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

    signingConfigs {
        create("release") {
            if (keystoreProperties.containsKey("keyAlias")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Usa a signing config de release se `key.properties` existir;
            // senão, cai para debug keys (desenvolvimento).
            signingConfig = if (keystoreProperties.containsKey("keyAlias")) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Minify + shrink reduzem o tamanho do APK/AAB. ProGuard mantém
            // as classes geradas por freezed/drift/json_serializable.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Lê a configuração de assinatura de `android/key.properties` (gitignored).
val keystoreProperties = Properties().apply {
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        load(FileInputStream(keystoreFile))
    }
}

val hasReleaseKey = keystoreProperties.containsKey("keyAlias")

// Escape para quando se quer um release sem a chave (medir tamanho do APK,
// testar o ProGuard). Explícito de propósito: o default é falhar.
//   flutter build apk --release -Pveredas.allowDebugSigning=true
val allowDebugSigning = (findProperty("veredas.allowDebugSigning") == "true")

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
            if (hasReleaseKey) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // **O build de release FALHA sem a chave, em vez de cair em debug
            // keys.** O fallback silencioso existia desde a Fase 10 e era
            // aceitável enquanto o destino era a Play Store, que recusa o
            // artefato e avisa. O app passou a ser distribuído como APK
            // instalado à mão (não há conta na Play), e aí o silêncio cobra
            // caro: um APK debug-signed **instala sem reclamar**, e o APK
            // seguinte — assinado com a chave de verdade — não instala em cima
            // dele (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Cada pessoa da base
            // teria de desinstalar o app e entrar de novo, e quem descobre
            // isso é o usuário, semanas depois.
            //
            // O `flutter build apk --debug` e o `--profile` usam outro build
            // type e não passam por aqui.
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                else -> throw GradleException(
                    "Build de release sem chave de assinatura.\n" +
                        "Falta android/key.properties (gitignored) apontando " +
                        "para o keystore em ~/.android-keys/veredas-upload.jks.\n" +
                        "Ver docs/LANCAMENTO.md.\n" +
                        "Para um release sem assinatura de verdade (só medir " +
                        "tamanho), passe -Pveredas.allowDebugSigning=true."
                )
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

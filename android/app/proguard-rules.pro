## Build de release — configuração de assinatura
##
## O keystore NÃO entra no repositório (regra de segurança do AGENTS.md §8).
## Coloque o arquivo em `android/app/veredas-release.jks` e preencha
## `android/key.properties` (gitignored) com:
##
## ```
## storePassword=SUA_SENHA
## keyPassword=SUA_SENHA
## keyAlias=veredas
## storeFile=veredas-release.jks
## ```
##
## Gerar keystore:
##   keytool -genkey -v -keystore android/app/veredas-release.jks \
##     -keyalg RSA -keysize 2048 -validity 10000 -alias veredas
##
## Sem `key.properties`, o build de release usa as debug keys (para
## desenvolvimento). Para publicar na Play Store, é obrigatório um keystore
## próprio — perder a chave significa perder a identidade do app.

# ProGuard — regras para o release build.
#
# O Flutter já injeta as regras necessárias para o próprio framework e para
# plugins via `consumer-rules.pro`. Estas regras extras protegem os modelos
# freezed/json_serializable e o drift, que usam reflection indireta.

# Mantém classes geradas pelo freezed (construtores nomeados, ==, hashCode).
-keep class **_$* { *; }
-keep class **.freezed { *; }
-keep @freezed class * { *; }

# Mantém classes geradas pelo json_serializable (fromJson/toJson).
-keep class **.g.dart { *; }
-keepclassmembers class * {
  @com.fasterxml.jackson.annotation.* <fields>;
}

# drift: mantém as classes de banco geradas e os conversores.
-keep class **_$*Database { *; }
-keep class **.drift.dart { *; }
-keep class * extends com.github.tametree.drift.runtime.DriftDatabase { *; }

# Mantém enums usados em serialização (AppRole, etc.).
-keepclassmembers enum * {
  public static **[] values();
  public static ** valueOf(java.lang.String);
}

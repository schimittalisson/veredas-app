/// Credenciais lidas em tempo de compilação via `--dart-define-from-file`.
///
/// Deliberadamente **não** usamos um `.env` declarado como asset: um asset fica
/// legível dentro do APK com um `unzip`. A `anon key` do Supabase é pública por
/// design — a proteção dos dados é o RLS, não o sigilo da chave — mas empacotar
/// segredos como asset é um hábito que eventualmente vaza algo que importa.
///
/// Rodar:
/// ```
/// flutter run --dart-define-from-file=env/dev.json
/// ```
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // --- Firebase (só para push) ---------------------------------------------
  //
  // Por dart-define, e não pelos arquivos `google-services.json` /
  // `GoogleService-Info.plist`: são os mesmos valores, mas sem arquivo novo
  // no repositório nem plugin de Gradle, e o build do Codemagic recebe tudo
  // pelo mesmo `env/prod.json` do Supabase. Os valores saem do console do
  // Firebase (Configurações do projeto → Seus apps); ver supabase/README.md, Passo 10.
  //
  // Nenhum deles é segredo: vão dentro de qualquer app Firebase publicado.
  // O que é segredo é a conta de serviço, que fica só na Edge Function.

  static const String firebaseApiKeyAndroid =
      String.fromEnvironment('FIREBASE_API_KEY_ANDROID');
  static const String firebaseApiKeyIos =
      String.fromEnvironment('FIREBASE_API_KEY_IOS');
  static const String firebaseAppIdAndroid =
      String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const String firebaseAppIdIos =
      String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const String firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String firebaseSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');

  /// Sem estes, o push fica desligado — e só ele. O lembrete da lavanderia é
  /// local e funciona do mesmo jeito.
  static bool firebaseConfiguredFor({required bool ios}) =>
      firebaseProjectId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      (ios
          ? firebaseApiKeyIos.isNotEmpty && firebaseAppIdIos.isNotEmpty
          : firebaseApiKeyAndroid.isNotEmpty &&
              firebaseAppIdAndroid.isNotEmpty);

  /// Falha cedo e com mensagem útil.
  ///
  /// Sem isto, o `Supabase.initialize` recebe uma URL vazia e o app quebra
  /// depois, com um erro de rede genérico que não indica a causa real
  /// (esquecer o `--dart-define-from-file` é o erro mais comum ao clonar).
  static void assertConfigured() {
    if (isConfigured) return;
    throw StateError(
      'SUPABASE_URL e SUPABASE_ANON_KEY não foram definidos.\n'
      'Rode o app com:\n'
      '  flutter run --dart-define-from-file=env/dev.json\n'
      'Crie o env/dev.json a partir de env/dev.example.json '
      '(ver supabase/README.md, passo 2).',
    );
  }
}

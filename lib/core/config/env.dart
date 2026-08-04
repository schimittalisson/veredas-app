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

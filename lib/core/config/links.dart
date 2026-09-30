/// Endereços públicos que o app abre no navegador.
class AppLinks {
  const AppLinks._();

  /// Termos de uso (`TERMOS.md` na raiz do repositório).
  ///
  /// No GitHub pelo mesmo motivo da política de privacidade: a App Store exige
  /// uma URL pública, e o arquivo versionado junto do código não fica velho em
  /// relação ao app. Se o repositório deixar de ser público, este link e o da
  /// política quebram juntos — troque os dois.
  static final Uri termsOfUse = Uri.parse(
    'https://github.com/schimittalisson/veredas-app/blob/main/TERMOS.md',
  );
}

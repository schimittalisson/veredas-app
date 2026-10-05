/// Papéis globais, espelhando o enum `public.app_role` do Postgres.
///
/// "Responsável por escala" **não** é um papel global: é uma atribuição por tipo
/// de escala, na tabela `scale_managers`. Um obreiro pode gerenciar a escala de
/// Lixo sem ter nenhum privilégio a mais em qualquer outro lugar do app.
enum AppRole {
  admin('admin'),
  obreiro('obreiro'),

  /// Aluno da ETED. Vê tudo o que o obreiro vê, menos o mural de oração
  /// (garantido por `is_member()` no servidor). No fim da escola, o admin o
  /// promove a obreiro ou o remove.
  aluno('aluno');

  const AppRole(this.wire);

  /// Valor exato gravado no banco. Não use `name` nem `toString()` na
  /// serialização — renomear o membro do enum quebraria os dados em produção
  /// em silêncio.
  final String wire;

  static AppRole fromWire(String? value) {
    return switch (value) {
      'admin' => AppRole.admin,
      'aluno' => AppRole.aluno,
      // Default seguro: qualquer valor desconhecido cai no papel de menor
      // privilégio. Se o servidor introduzir um papel novo, um app antigo
      // trata a pessoa como obreiro em vez de conceder acesso indevido.
      _ => AppRole.obreiro,
    };
  }
}

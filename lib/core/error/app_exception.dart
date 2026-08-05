/// Códigos de erro do app.
///
/// A UI escolhe a mensagem do l10n **a partir deste código**, nunca a partir do
/// texto da exceção original. Isso é uma regra, não preferência: mensagens de
/// `PostgrestException` e `AuthException` vêm em inglês, mudam entre versões do
/// SDK e às vezes carregam o payload da requisição — inclusive dados pessoais.
enum AppErrorCode {
  // --- Rede / infraestrutura ---
  noConnection,
  timeout,
  serverUnavailable,

  // --- Autenticação ---
  invalidCredentials,
  emailNotConfirmed,
  emailAlreadyRegistered,
  weakPassword,
  sessionExpired,
  notAuthenticated,

  // --- Convite (erros da RPC redeem_invite) ---
  inviteNotFound,
  inviteExpired,
  inviteExhausted,
  inviteRevoked,

  // --- Permissão ---
  /// O RLS recusou a escrita, ou a linha foi alterada/removida por outra
  /// pessoa. Os dois casos são indistinguíveis num `UPDATE` que afeta 0 linhas
  /// (ver `permissionDeniedOrStale`).
  permissionDenied,

  /// A operação foi recusada por uma RPC (ex.: admin tentando rebaixar a si
  /// mesmo sendo o único admin). Diferente de [permissionDenied] (RLS):
  /// a recusa é explícita, com uma mensagem específica.
  forbidden,

  /// Escrita que não afetou nenhuma linha.
  ///
  /// Existe separado de [permissionDenied] porque a causa é ambígua: pode ser
  /// RLS negando ou a linha ter sido removida no servidor. O tratamento técnico
  /// é o mesmo (reverter e ressincronizar), mas a mensagem ao usuário precisa
  /// ser honesta — dizer "sem permissão" quando o item foi apagado por outra
  /// pessoa confunde.
  permissionDeniedOrStale,

  notApproved,

  // --- Dados ---
  notFound,
  conflict,
  validation,

  /// Nada previsto casou. A UI mostra uma mensagem genérica.
  unknown,
}

/// Exceção única que atravessa a fronteira entre dados e UI.
///
/// Nenhuma exceção de Supabase ou drift chega à camada de apresentação: tudo é
/// convertido aqui pelo `error_mapper`.
class AppException implements Exception {
  const AppException(
    this.code, {
    this.debugMessage,
    this.cause,
    this.stackTrace,
  });

  final AppErrorCode code;

  /// Detalhe técnico para log e depuração. **Nunca exibido ao usuário.**
  final String? debugMessage;

  final Object? cause;
  final StackTrace? stackTrace;

  /// Vale tentar de novo? Usado pelo `OutboxWorker` para decidir entre manter o
  /// item na fila (com backoff) ou descartá-lo e reverter o cache.
  bool get isRetryable => switch (code) {
        AppErrorCode.noConnection ||
        AppErrorCode.timeout ||
        AppErrorCode.serverUnavailable =>
          true,
        _ => false,
      };

  /// A escrita foi definitivamente recusada, então o cache otimista precisa ser
  /// revertido.
  bool get requiresRollback => switch (code) {
        AppErrorCode.permissionDenied ||
        AppErrorCode.permissionDeniedOrStale ||
        AppErrorCode.notApproved ||
        AppErrorCode.forbidden ||
        AppErrorCode.conflict ||
        AppErrorCode.validation ||
        AppErrorCode.notFound =>
          true,
        _ => false,
      };

  @override
  String toString() =>
      'AppException(${code.name}${debugMessage == null ? '' : ': $debugMessage'})';
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/core/error/app_exception.dart';

/// Converte qualquer exceção da camada de dados em [AppException].
///
/// Ponto único de tradução: se um erro novo aparecer, o conserto é aqui, e não
/// espalhado em cada `catch` de tela.
AppException mapError(Object error, [StackTrace? stackTrace]) {
  if (error is AppException) return error;

  if (error is PostgrestException) {
    return _mapPostgrest(error, stackTrace);
  }
  if (error is AuthException) {
    return _mapAuth(error, stackTrace);
  }
  if (error is StorageException) {
    return AppException(
      // O Storage devolve o status como String.
      error.statusCode == '403' || error.statusCode == '401'
          ? AppErrorCode.permissionDenied
          : AppErrorCode.unknown,
      debugMessage: 'Storage ${error.statusCode}',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // Falha de um plugin nativo. Na prática é sempre o armazenamento seguro:
  // no iOS o Keychain devolve `-34018 errSecMissingEntitlement` quando o build
  // não tem a capability de Keychain Sharing, e o flutter_secure_storage
  // repassa isso como PlatformException. Manter o `code` do plugin no
  // debugMessage é o que permite distinguir isso de um erro de rede no log.
  if (error is PlatformException) {
    return AppException(
      AppErrorCode.deviceStorage,
      debugMessage: 'PlatformException ${error.code}',
      cause: error,
      stackTrace: stackTrace,
    );
  }
  // O plugin não foi registrado no build (acontece em teste de widget sem
  // mock, e em builds onde o registrant não incluiu o plugin).
  if (error is MissingPluginException) {
    return AppException(
      AppErrorCode.deviceStorage,
      debugMessage: 'MissingPluginException',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // Rede. SocketException cobre DNS e host inalcançável; ClientException do
  // http cobre conexão derrubada no meio.
  if (error is SocketException) {
    return AppException(
      AppErrorCode.noConnection,
      debugMessage: 'SocketException',
      cause: error,
      stackTrace: stackTrace,
    );
  }
  if (error is TimeoutException) {
    return AppException(
      AppErrorCode.timeout,
      debugMessage: 'TimeoutException',
      cause: error,
      stackTrace: stackTrace,
    );
  }
  if (error is HandshakeException || error is HttpException) {
    return AppException(
      AppErrorCode.noConnection,
      debugMessage: error.runtimeType.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  return AppException(
    AppErrorCode.unknown,
    // Só o tipo, deliberadamente: `error.toString()` de uma PostgrestException
    // pode conter o payload da requisição, com dados pessoais, e isto vai para
    // o log.
    debugMessage: error.runtimeType.toString(),
    cause: error,
    stackTrace: stackTrace,
  );
}

AppException _mapPostgrest(PostgrestException e, StackTrace? st) {
  // Os erros da RPC redeem_invite chegam como `raise exception`, que o
  // Postgres reporta com SQLSTATE P0001 e a mensagem sendo o nome que
  // escolhemos no SQL. É por isso que o docs/SCHEMA.md usa códigos em maiúsculas em
  // vez de texto legível: eles são identificadores estáveis, não mensagens.
  final message = e.message.toUpperCase();
  if (message.contains('INVITE_NOT_FOUND')) {
    return AppException(AppErrorCode.inviteNotFound, cause: e, stackTrace: st);
  }
  if (message.contains('INVITE_EXPIRED')) {
    return AppException(AppErrorCode.inviteExpired, cause: e, stackTrace: st);
  }
  if (message.contains('INVITE_EXHAUSTED')) {
    return AppException(AppErrorCode.inviteExhausted, cause: e, stackTrace: st);
  }
  if (message.contains('INVITE_REVOKED')) {
    return AppException(AppErrorCode.inviteRevoked, cause: e, stackTrace: st);
  }
  if (message.contains('INVITE_CODE_TAKEN')) {
    return AppException(AppErrorCode.inviteCodeTaken, cause: e, stackTrace: st);
  }
  // O admin mandou um limite <= 0 ou um código vazio: erro de formulário, não
  // de permissão.
  if (message.contains('INVALID_MAX_USES') ||
      message.contains('INVALID_INVITE_CODE')) {
    return AppException(AppErrorCode.validation, cause: e, stackTrace: st);
  }
  if (message.contains('NOT_AUTHENTICATED')) {
    return AppException(AppErrorCode.notAuthenticated, cause: e, stackTrace: st);
  }
  if (message.contains('LAUNDRY_SLOT_BLOCKED')) {
    return AppException(AppErrorCode.laundrySlotBlocked,
        cause: e, stackTrace: st);
  }
  if (message.contains('LAUNDRY_PAST_DATE')) {
    return AppException(AppErrorCode.laundryPastDate, cause: e, stackTrace: st);
  }
  // A máquina ou a faixa saiu do cadastro entre o desenho da grade e o toque.
  // Do ponto de vista de quem tocou, é o mesmo caso de "atualize a planilha".
  if (message.contains('LAUNDRY_MACHINE_NOT_FOUND') ||
      message.contains('LAUNDRY_TIME_SLOT_NOT_FOUND') ||
      message.contains('LAUNDRY_RESERVATION_NOT_FOUND')) {
    return AppException(AppErrorCode.conflict, cause: e, stackTrace: st);
  }
  if (message.contains('FORBIDDEN_NOT_OWNER') ||
      message.contains('FORBIDDEN_NOT_ADMIN') ||
      message.contains('FORBIDDEN_NOT_APPROVED')) {
    return AppException(AppErrorCode.permissionDenied, cause: e, stackTrace: st);
  }
  if (message.contains('FORBIDDEN_PRIVILEGE_CHANGE')) {
    return AppException(AppErrorCode.permissionDenied, cause: e, stackTrace: st);
  }

  final code = switch (e.code) {
    // 42501 insufficient_privilege: o RLS recusou no WITH CHECK.
    '42501' => AppErrorCode.permissionDenied,
    '401' || '403' => AppErrorCode.permissionDenied,
    // 23505 unique_violation, 23503 foreign_key_violation.
    '23505' || '409' => AppErrorCode.conflict,
    '23503' => AppErrorCode.conflict,
    // 23514 check_violation: constraint de domínio (título curto demais etc.).
    '23514' || '400' || '422' => AppErrorCode.validation,
    '404' || 'PGRST116' => AppErrorCode.notFound,
    '500' || '502' || '503' || '504' => AppErrorCode.serverUnavailable,
    _ => null,
  };
  if (code != null) {
    return AppException(
      code,
      debugMessage: 'Postgrest ${e.code}',
      cause: e,
      stackTrace: st,
    );
  }

  // PGRST301 / JWT expirado.
  if (message.contains('JWT') && message.contains('EXPIRED')) {
    return AppException(AppErrorCode.sessionExpired, cause: e, stackTrace: st);
  }

  return AppException(
    AppErrorCode.unknown,
    debugMessage: 'Postgrest ${e.code}',
    cause: e,
    stackTrace: st,
  );
}

AppException _mapAuth(AuthException e, StackTrace? st) {
  final message = e.message.toLowerCase();

  // A comparação é por substring de propósito: o gotrue muda o texto exato
  // entre versões, e `code` nem sempre vem preenchido.
  if (message.contains('invalid login credentials') ||
      message.contains('invalid credentials')) {
    return AppException(
      AppErrorCode.invalidCredentials,
      cause: e,
      stackTrace: st,
    );
  }
  if (message.contains('email not confirmed')) {
    return AppException(
      AppErrorCode.emailNotConfirmed,
      cause: e,
      stackTrace: st,
    );
  }
  // Confirmação por código. O gotrue devolve `otp_expired` tanto para código
  // vencido quanto para código já usado, e a mensagem junta os dois casos
  // ("Token has expired or is invalid"). Expirado é o palpite mais útil: um
  // código digitado errado costuma cair no ramo `otpInvalid` abaixo, com 403.
  if (e.code == 'otp_expired' || message.contains('has expired')) {
    return AppException(AppErrorCode.otpExpired, cause: e, stackTrace: st);
  }
  if (e.code == 'otp_disabled' ||
      (message.contains('token') && message.contains('invalid')) ||
      (message.contains('otp') && message.contains('invalid'))) {
    return AppException(AppErrorCode.otpInvalid, cause: e, stackTrace: st);
  }

  if (message.contains('already registered') ||
      message.contains('already been registered') ||
      e.code == 'user_already_exists') {
    return AppException(
      AppErrorCode.emailAlreadyRegistered,
      cause: e,
      stackTrace: st,
    );
  }
  if (message.contains('password') &&
      (message.contains('at least') || message.contains('weak'))) {
    return AppException(AppErrorCode.weakPassword, cause: e, stackTrace: st);
  }
  if (message.contains('jwt') || message.contains('session')) {
    return AppException(AppErrorCode.sessionExpired, cause: e, stackTrace: st);
  }

  return AppException(
    AppErrorCode.unknown,
    debugMessage: 'Auth ${e.statusCode ?? ''}'.trim(),
    cause: e,
    stackTrace: st,
  );
}

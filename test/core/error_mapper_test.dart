import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/error/error_mapper.dart';

void main() {
  group('mapError — RPC de convite', () {
    // A RPC redeem_invite usa `raise exception 'INVITE_NOT_FOUND'`, que chega
    // como PostgrestException com a mensagem sendo o próprio código. É por isso
    // que o SCHEMA.md usa identificadores em maiúsculas e não frases.
    test('INVITE_NOT_FOUND', () {
      final e = mapError(PostgrestException(message: 'INVITE_NOT_FOUND'));
      expect(e.code, AppErrorCode.inviteNotFound);
    });

    test('INVITE_EXPIRED', () {
      final e = mapError(PostgrestException(message: 'INVITE_EXPIRED'));
      expect(e.code, AppErrorCode.inviteExpired);
    });

    test('INVITE_EXHAUSTED', () {
      final e = mapError(PostgrestException(message: 'INVITE_EXHAUSTED'));
      expect(e.code, AppErrorCode.inviteExhausted);
    });

    test('INVITE_REVOKED', () {
      final e = mapError(PostgrestException(message: 'INVITE_REVOKED'));
      expect(e.code, AppErrorCode.inviteRevoked);
    });

    test('reconhece o código dentro da mensagem verbosa do Postgres', () {
      // O Postgres embrulha: 'ERROR: INVITE_EXPIRED (SQLSTATE P0001)'.
      final e = mapError(
        PostgrestException(message: 'ERROR: INVITE_EXPIRED (SQLSTATE P0001)'),
      );
      expect(e.code, AppErrorCode.inviteExpired);
    });
  });

  group('mapError — permissão', () {
    test('42501 do RLS vira permissionDenied', () {
      final e = mapError(
        PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        ),
      );
      expect(e.code, AppErrorCode.permissionDenied);
      expect(e.requiresRollback, isTrue);
      expect(e.isRetryable, isFalse);
    });

    test('FORBIDDEN_PRIVILEGE_CHANGE do trigger vira permissionDenied', () {
      final e = mapError(
        PostgrestException(message: 'FORBIDDEN_PRIVILEGE_CHANGE'),
      );
      expect(e.code, AppErrorCode.permissionDenied);
    });

    test('NOT_AUTHENTICATED', () {
      final e = mapError(PostgrestException(message: 'NOT_AUTHENTICATED'));
      expect(e.code, AppErrorCode.notAuthenticated);
    });
  });

  group('mapError — dados', () {
    test('unique_violation vira conflict', () {
      final e = mapError(
        PostgrestException(message: 'duplicate key', code: '23505'),
      );
      expect(e.code, AppErrorCode.conflict);
      expect(e.requiresRollback, isTrue);
    });

    test('check_violation vira validation', () {
      // Ex.: título de oração fora do range 3..120 do CHECK do servidor.
      final e = mapError(
        PostgrestException(message: 'violates check constraint', code: '23514'),
      );
      expect(e.code, AppErrorCode.validation);
    });

    test('5xx vira serverUnavailable e É retentável', () {
      final e = mapError(
        PostgrestException(message: 'bad gateway', code: '503'),
      );
      expect(e.code, AppErrorCode.serverUnavailable);
      expect(e.isRetryable, isTrue);
      expect(e.requiresRollback, isFalse);
    });
  });

  group('mapError — rede', () {
    test('SocketException vira noConnection e É retentável', () {
      final e = mapError(const SocketException('falha de DNS'));
      expect(e.code, AppErrorCode.noConnection);
      expect(e.isRetryable, isTrue);
      // Crucial: erro de rede NÃO reverte o cache. A escrita continua na fila.
      expect(e.requiresRollback, isFalse);
    });

    test('TimeoutException vira timeout e É retentável', () {
      final e = mapError(TimeoutException('demorou'));
      expect(e.code, AppErrorCode.timeout);
      expect(e.isRetryable, isTrue);
      expect(e.requiresRollback, isFalse);
    });
  });

  group('mapError — auth', () {
    test('credenciais inválidas', () {
      final e = mapError(const AuthException('Invalid login credentials'));
      expect(e.code, AppErrorCode.invalidCredentials);
    });

    test('e-mail não confirmado', () {
      final e = mapError(const AuthException('Email not confirmed'));
      expect(e.code, AppErrorCode.emailNotConfirmed);
    });

    test('e-mail já cadastrado', () {
      final e = mapError(
        const AuthException('User already registered'),
      );
      expect(e.code, AppErrorCode.emailAlreadyRegistered);
    });

    test('senha fraca', () {
      final e = mapError(
        const AuthException('Password should be at least 8 characters'),
      );
      expect(e.code, AppErrorCode.weakPassword);
    });
  });

  group('mapError — contrato geral', () {
    test('não re-embrulha uma AppException', () {
      const original = AppException(AppErrorCode.inviteExpired);
      expect(mapError(original), same(original));
    });

    test('desconhecido vira unknown', () {
      final e = mapError(Exception('algo bem estranho'));
      expect(e.code, AppErrorCode.unknown);
    });

    test('debugMessage não vaza o conteúdo do erro original', () {
      // Regra de segurança: PostgrestException.toString() pode carregar o
      // payload da requisição, com dados pessoais, e isto vai para o log.
      final e = mapError(
        Exception('senha=hunter2 email=alguem@exemplo.com'),
      );
      expect(e.debugMessage, isNot(contains('hunter2')));
      expect(e.debugMessage, isNot(contains('alguem@exemplo.com')));
    });

    test('permissionDeniedOrStale reverte, como o permissionDenied', () {
      // O caso do UPDATE que afeta 0 linhas: o RLS filtra em silêncio, sem
      // erro. Se o worker tratar isso como sucesso, o cache local divergirá do
      // servidor para sempre.
      const e = AppException(AppErrorCode.permissionDeniedOrStale);
      expect(e.requiresRollback, isTrue);
      expect(e.isRetryable, isFalse);
    });
  });
}

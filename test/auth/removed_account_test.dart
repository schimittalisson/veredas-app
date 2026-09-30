import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/data/remote/supabase_auth_service.dart';

// Quem foi removido da base continua com o login no Supabase. Ao tentar se
// cadastrar de novo, o Supabase finge que deu certo e não envia código; ao
// entrar com a senha antiga, a pessoa caía em "aguardando aprovação". Os dois
// sinais que o app usa para explicar o que fazer estão aqui.

User _user({required List<Map<String, dynamic>> identities}) => User.fromJson({
      'id': 'u1',
      'aud': 'authenticated',
      'created_at': '2026-09-30T12:00:00Z',
      'identities': identities,
    })!;

void main() {
  group('signUpHitExistingAccount', () {
    test('usuário sem identidade = e-mail que já tinha conta', () {
      // É a resposta "de fachada" do Supabase para um e-mail existente.
      expect(
        SupabaseAuthService.signUpHitExistingAccount(_user(identities: [])),
        isTrue,
      );
    });

    test('cadastro novo de verdade traz a identidade de e-mail', () {
      final user = _user(identities: [
        {
          'id': 'i1',
          'user_id': 'u1',
          'identity_id': 'i1',
          'provider': 'email',
        },
      ]);
      expect(SupabaseAuthService.signUpHitExistingAccount(user), isFalse);
    });

    test('sem usuário na resposta não é o caso', () {
      expect(SupabaseAuthService.signUpHitExistingAccount(null), isFalse);
    });
  });

  group('removalCodeFor', () {
    test('perfil ativo entra', () {
      expect(
        SupabaseAuthService.removalCodeFor({
          'deleted_at': null,
          'email': 'julia@teste.com',
        }),
        isNull,
      );
    });

    test('removido por admin: pedir restauração', () {
      expect(
        SupabaseAuthService.removalCodeFor({
          'deleted_at': '2026-09-30T12:00:00Z',
          'email': 'julia@teste.com',
        }),
        AppErrorCode.accountRemoved,
      );
    });

    test('excluiu a própria conta (e-mail apagado): não há restauração', () {
      expect(
        SupabaseAuthService.removalCodeFor({
          'deleted_at': '2026-09-30T12:00:00Z',
          'email': null,
        }),
        AppErrorCode.accountDeleted,
      );
    });

    test('perfil que não veio (sem rede, ainda sem linha) não barra', () {
      expect(SupabaseAuthService.removalCodeFor(null), isNull);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/models/profile.dart';
import 'package:veredas/data/remote/auth_service.dart';
import 'package:veredas/data/sync/connectivity_monitor.dart';
import 'package:veredas/data/sync/remote_source.dart';
import 'package:veredas/providers/auth_providers.dart';

// Silencia o warning de "múltiplas instâncias do banco" — cada teste cria
// seu próprio NativeDatabase.memory(), então não há risco de corrida.
void _silenceDriftWarnings() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// Banco drift em memória, isolado por teste.
///
/// `NativeDatabase.memory()` usa a `libsqlite3` do sistema — por isso o
/// `libsqlite3-dev` é requisito para rodar os testes no desktop
/// (`sudo apt install libsqlite3-dev`).
AppDatabase createTestDatabase() {
  _silenceDriftWarnings();
  return AppDatabase.forTesting(NativeDatabase.memory());
}

// ---------------------------------------------------------------------------
// FakeRemoteSource — fonte remota controlada para testes de sync/outbox.
//
// Em vez de mockar a cadeia fluent do supabase_flutter (PostgrestQueryBuilder
// → PostgrestFilterBuilder → ...), que é frágil e acoplada a tipos internos
// do SDK, a fake implementa RemoteSource diretamente. Cada método retorna
// dados pré-configurados ou lança a exceção programada.
// ---------------------------------------------------------------------------

/// Registro de uma chamada feita à FakeRemoteSource.
typedef RemoteCall = ({String method, String table, Map<String, dynamic>? extra});

class FakeRemoteSource implements RemoteSource {
  FakeRemoteSource();

  /// Dados que `fetch` devolve, por tabela.
  final Map<String, List<Map<String, dynamic>>> fetchData = {};

  /// Exceção a lançar no próximo `fetch` de uma tabela, por tabela.
  final Map<String, Object> fetchErrors = {};

  /// Exceção a lançar no próximo `insert`, por tabela.
  final Map<String, Object> insertErrors = {};

  /// Exceção a lançar no próximo `update`, por tabela.
  final Map<String, Object> updateErrors = {};

  /// Exceção a lançar no próximo `delete`, por tabela.
  final Map<String, Object> deleteErrors = {};

  /// Resultado do próximo `update`, por tabela. Default: `[{'id': 'x'}]`
  /// (1 linha afetada). Use `[]` para simular 0-linhas.
  final Map<String, List<Map<String, dynamic>>> updateResults = {};

  /// Resultado do próximo `delete`, por tabela.
  final Map<String, List<Map<String, dynamic>>> deleteResults = {};

  /// Histórico de chamadas, em ordem.
  final List<RemoteCall> calls = [];

  /// Payloads recebidos em `insert`, por tabela.
  final Map<String, List<Map<String, dynamic>>> insertedPayloads = {};

  /// Payloads recebidos em `update`, por tabela.
  final Map<String, List<Map<String, dynamic>>> updatedPayloads = {};

  @override
  Future<List<Map<String, dynamic>>> fetch({
    required String table,
    String? gtColumn,
    Object? gtValue,
    String? orderColumn,
  }) async {
    calls.add((
      method: 'fetch',
      table: table,
      extra: {'gtColumn': gtColumn, 'gtValue': gtValue, 'orderColumn': orderColumn},
    ));
    if (fetchErrors.containsKey(table)) {
      final e = fetchErrors.remove(table)!;
      throw e;
    }
    return fetchData[table] ?? [];
  }

  @override
  Future<void> insert({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    calls.add((method: 'insert', table: table, extra: payload));
    if (insertErrors.containsKey(table)) {
      final e = insertErrors.remove(table)!;
      throw e;
    }
    insertedPayloads.putIfAbsent(table, () => []).add(payload);
  }

  @override
  Future<List<Map<String, dynamic>>> update({
    required String table,
    required Map<String, dynamic> payload,
    required String eqColumn,
    required Object eqValue,
  }) async {
    calls.add((method: 'update', table: table, extra: {'eqColumn': eqColumn, 'eqValue': eqValue, ...payload}));
    if (updateErrors.containsKey(table)) {
      final e = updateErrors.remove(table)!;
      throw e;
    }
    updatedPayloads.putIfAbsent(table, () => []).add(payload);
    return updateResults[table] ?? [{'id': eqValue}];
  }

  @override
  Future<List<Map<String, dynamic>>> delete({
    required String table,
    required String eqColumn,
    required Object eqValue,
  }) async {
    calls.add((method: 'delete', table: table, extra: {'eqColumn': eqColumn, 'eqValue': eqValue}));
    if (deleteErrors.containsKey(table)) {
      final e = deleteErrors.remove(table)!;
      throw e;
    }
    return deleteResults[table] ?? [{'id': eqValue}];
  }

  void reset() {
    fetchData.clear();
    fetchErrors.clear();
    insertErrors.clear();
    updateErrors.clear();
    deleteErrors.clear();
    updateResults.clear();
    deleteResults.clear();
    calls.clear();
    insertedPayloads.clear();
    updatedPayloads.clear();
  }
}

// ---------------------------------------------------------------------------
// FakeConnectivityMonitor — conectividade controlada para testes.
//
// Mantém `current()` e `changes()` separados de propósito: é exatamente essa
// distinção que o bug de conectividade explorava. Um monitor que só entrega
// `changes()` (o que o provider fazia antes) deixa o app sem saber se há rede.
// ---------------------------------------------------------------------------

class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor({
    this.currentResult = const [ConnectivityResult.wifi],
  });

  /// O que `current()` devolve.
  List<ConnectivityResult> currentResult;

  /// Quantas vezes `current()` foi chamado — o provider deve consultá-lo.
  int currentCalls = 0;

  // Controller de assinatura única, e **não** broadcast: um broadcast descarta
  // eventos emitidos enquanto não há assinante, e o assinante aqui é um
  // `async*` que só chega ao `yield* changes()` depois de resolver o
  // `current()`. Um `emit()` logo após o estado inicial caía nessa janela e o
  // teste passava ou falhava conforme o que houvesse de `await` no meio. Com
  // assinatura única os eventos ficam bufferizados até a inscrição.
  final StreamController<List<ConnectivityResult>> _changes =
      StreamController<List<ConnectivityResult>>();

  @override
  Future<List<ConnectivityResult>> current() async {
    currentCalls++;
    return currentResult;
  }

  @override
  Stream<List<ConnectivityResult>> changes() => _changes.stream;

  /// Simula uma mudança de rede vinda do sistema.
  void emit(List<ConnectivityResult> result) {
    currentResult = result;
    _changes.add(result);
  }

  void dispose() => _changes.close();
}

// ---------------------------------------------------------------------------
// Fábricas de modelos (JSON no formato PostgREST — snake_case, ISO strings).
// ---------------------------------------------------------------------------

Map<String, dynamic> makeProfileJson({
  String id = 'p1',
  String fullName = 'Maria Silva',
  String? email = 'maria@veredas.org',
  String? phone,
  String? avatarUrl,
  String? bio,
  String role = 'obreiro',
  bool isApproved = true,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return {
    'id': id,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'avatar_url': avatarUrl,
    'bio': bio,
    'role': role,
    'is_approved': isApproved,
    'created_at': (createdAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
  };
}

Map<String, dynamic> makeEventJson({
  String id = 'e1',
  String title = 'Reunião de obreiros',
  String? description,
  DateTime? startsAt,
  DateTime? endsAt,
  bool allDay = false,
  String? location,
  String? category,
  String? coverImageUrl,
  String? createdBy,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return {
    'id': id,
    'title': title,
    'description': description,
    'starts_at': (startsAt ?? DateTime.utc(2026, 8, 15, 19, 0)).toIso8601String(),
    'ends_at': endsAt?.toIso8601String(),
    'all_day': allDay,
    'location': location,
    'category': category,
    'cover_image_url': coverImageUrl,
    'created_by': createdBy,
    'updated_at': (updatedAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
  };
}

Map<String, dynamic> makeAnnouncementJson({
  String id = 'a1',
  String? authorId,
  String? title = 'Aviso importante',
  String body = 'Reunião sexta às 19h',
  bool pinned = false,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return {
    'id': id,
    'author_id': authorId,
    'title': title,
    'body': body,
    'pinned': pinned,
    'created_at': (createdAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
  };
}

Map<String, dynamic> makeScaleManagerJson({
  String scaleTypeId = 'st1',
  String userId = 'u1',
  DateTime? updatedAt,
}) {
  return {
    'scale_type_id': scaleTypeId,
    'user_id': userId,
    'updated_at': (updatedAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Helpers para criar entradas na outbox.
// ---------------------------------------------------------------------------

/// Cria e insere uma entrada na outbox, retornando o rowId.
///
/// Para simular uma escrita otimista: o repositório insere a linha no cache e
/// a entrada na outbox numa transação. Aqui fazemos o mesmo manualmente.
Future<int> enqueueOutboxEntry(
  AppDatabase db, {
  required String entity,
  required String op,
  required String rowId,
  Map<String, dynamic>? payload,
  Map<String, dynamic>? previousRow,
}) async {
  return db.into(db.outboxEntries).insert(
        OutboxEntriesCompanion.insert(
          entity: entity,
          op: op,
          rowId: rowId,
          payload: jsonEncode(payload ?? {}),
          previousRow: previousRow != null ? Value(jsonEncode(previousRow)) : const Value.absent(),
          createdAt: DateTime.now(),
        ),
      );
}

/// Cria uma PostgrestException simulando RLS negando (42501).
PostgrestException makeRlsException({String? code = '42501'}) {
  return PostgrestException(
    message: 'Permission denied',
    code: code,
    details: '',
    hint: '',
  );
}

/// Cria uma SocketException simulando falta de rede.
SocketException makeSocketException() {
  return const SocketException('Failed host lookup');
}

// ---------------------------------------------------------------------------
// FakeAuthService — auth controlado para testes.
//
// Implementa AuthService com um stream controlado por um StreamController.
// Cada método retorna dados pré-configurados ou lança a exceção programada.
// ---------------------------------------------------------------------------

class FakeAuthService implements AuthService {
  FakeAuthService();

  // Broadcast sync: emite imediatamente. O authStateChanges abaixo
  // precede o stream com o estado atual, então o StreamProvider sempre
  // resolve (não fica em loading).
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast(sync: true);

  /// Estado atual (o que get currentSession devolve).
  AuthState _currentState = AuthState.unauthenticated;

  /// Código de convite pendente guardado (simula secure storage).
  String? _pendingInviteCode;

  /// Exceção a lançar no próximo signIn.
  dynamic signInError;

  /// Exceção a lançar no próximo signUpWithInvite.
  dynamic signUpError;

  /// Exceção a lançar no próximo redeemPendingInvite.
  dynamic redeemError;

  /// Papel devolvido pelo redeem. Default: obreiro.
  AppRole redeemResult = AppRole.obreiro;

  /// Se o signUp devolve sessão (email confirmation desativado) ou não.
  bool signUpReturnsSession = true;

  /// Histórico de chamadas.
  final List<String> calls = [];

  /// Payloads recebidos em signUpWithInvite.
  Map<String, dynamic>? lastSignUpPayload;

  @override
  Stream<AuthState> get authStateChanges {
    // Cria um stream que emite o estado atual quando o primeiro listener
    // inscreve (onListen), e depois repassa os eventos do controller.
    // Isto imita o comportamento do Supabase, que emite o estado atual ao
    // inscrever.
    late StreamController<AuthState> sc;
    sc = StreamController<AuthState>.broadcast(
      sync: true,
      onListen: () => sc.add(_currentState),
    );
    _controller.stream.listen((s) => sc.add(s));
    return sc.stream;
  }

  @override
  Session? get currentSession => _currentState.session;

  /// Simula um login bem-sucedido.
  void simulateAuthenticated({String userId = 'test-user-id'}) {
    // Cria um User fake. O construtor de User do gotrue é interno, então
    // usamos o estado diretamente.
    _currentState = AuthState(
      session: null,
      user: _FakeUser(id: userId),
    );
    _controller.add(_currentState);
  }

  /// Simula a sessão criada por um link de recuperação de senha.
  void simulatePasswordRecovery({String userId = 'test-user-id'}) {
    _currentState = AuthState(
      session: null,
      user: _FakeUser(id: userId),
      event: AuthChangeEvent.passwordRecovery,
    );
    _controller.add(_currentState);
  }

  /// Simula logout.
  void simulateUnauthenticated() {
    _currentState = AuthState.unauthenticated;
    _controller.add(_currentState);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (signInError != null) {
      final e = signInError;
      signInError = null;
      throw e;
    }
    simulateAuthenticated();
  }

  @override
  Future<bool> signUpWithInvite({
    required String fullName,
    required String email,
    required String password,
    required String inviteCode,
    String? phone,
  }) async {
    calls.add('signUp:$email:$inviteCode');
    lastSignUpPayload = {
      'fullName': fullName,
      'email': email,
      'inviteCode': inviteCode,
      'phone': phone,
    };
    if (signUpError != null) {
      final e = signUpError;
      signUpError = null;
      throw e;
    }
    if (signUpReturnsSession) {
      simulateAuthenticated();
      // redeem é chamado internamente
      await _callRedeem(inviteCode);
      return true;
    } else {
      // Guarda o código para resgate posterior
      _pendingInviteCode = inviteCode;
      return false;
    }
  }

  /// Exceção a lançar no próximo verifyEmailOtp.
  dynamic verifyOtpError;

  @override
  Future<AppRole?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    calls.add('verifyOtp:$email:$token');
    if (verifyOtpError != null) {
      final e = verifyOtpError;
      verifyOtpError = null;
      throw e;
    }
    simulateAuthenticated();
    final pending = _pendingInviteCode;
    if (pending == null) return null;
    try {
      final role = await _callRedeem(pending);
      _pendingInviteCode = null;
      return role;
    } catch (_) {
      // Igual à implementação real: o e-mail já foi confirmado, então um
      // convite inválido não relança — o /aguardando pede o código de novo.
      return null;
    }
  }

  @override
  Future<AppRole?> redeemPendingInvite(String inviteCode) async {
    return _callRedeem(inviteCode);
  }

  Future<AppRole?> _callRedeem(String code) async {
    calls.add('redeem:$code');
    if (redeemError != null) {
      final e = redeemError;
      redeemError = null;
      throw e;
    }
    return redeemResult;
  }

  @override
  Future<String?> getPendingInviteCode() async => _pendingInviteCode;

  @override
  Future<void> clearPendingInvite() async {
    _pendingInviteCode = null;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    simulateUnauthenticated();
  }

  /// Erro a lançar em `deleteOwnAccount`, para o teste do caso "último admin".
  AppException? deleteAccountError;

  @override
  Future<void> deleteOwnAccount() async {
    calls.add('deleteOwnAccount');
    if (deleteAccountError != null) throw deleteAccountError!;
    // O serviço real encerra a sessão depois de apagar; o fake espelha isso,
    // senão o teste não veria o efeito que a UI depende (o redirect).
    simulateUnauthenticated();
  }

  @override
  Future<void> resetPassword(String email) async {
    calls.add('resetPassword:$email');
  }

  /// Exceção a lançar no próximo updatePassword.
  dynamic updatePasswordError;

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    if (updatePasswordError != null) {
      final e = updatePasswordError;
      updatePasswordError = null;
      throw e;
    }
  }

  @override
  Future<void> resendEmailConfirmation(String email) async {
    calls.add('resendConfirmation:$email');
  }

  @override
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    calls.add('updateProfile');
  }

  void dispose() {
    _controller.close();
  }
}

/// User fake para testes. O `User` do gotrue tem construtor interno, então
/// criamos uma classe mínima que satisfaz o tipo.
class _FakeUser implements User {
  _FakeUser({required this.id});

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Cria uma AppException para usar nos testes de auth.
AppException makeAuthException(AppErrorCode code) {
  return AppException(code);
}

// ---------------------------------------------------------------------------
// Esperas sobre providers
// ---------------------------------------------------------------------------

/// Um `Ref` do container.
///
/// Serve para chamar código que recebe `Ref` — como o `redirectForTest` do
/// router — de dentro de um teste, que só tem um `ProviderContainer`.
final refProvider = Provider<Ref>((ref) => ref);

/// Aguarda o authStateProvider emitir um estado que satisfaz [test].
Future<AuthState> waitForAuthState(
  ProviderContainer container,
  bool Function(AuthState) test,
) async {
  final completer = Completer<AuthState>();
  final sub = container.listen<AsyncValue<AuthState>>(
    authStateProvider,
    (_, value) {
      if (value.hasValue && !completer.isCompleted && test(value.value!)) {
        completer.complete(value.value!);
      }
    },
    fireImmediately: true,
  );
  final result = await completer.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw TimeoutException('authStateProvider não emitiu'),
  );
  sub.close();
  return result;
}

/// Aguarda o currentProfileProvider emitir um valor que satisfaz [test].
/// Para null, use (p) => p == null. Para non-null, use (p) => p != null.
Future<Profile?> waitForProfile(
  ProviderContainer container,
  bool Function(Profile?) test,
) async {
  final completer = Completer<Profile?>();
  final sub = container.listen<AsyncValue<Profile?>>(
    currentProfileProvider,
    (_, value) {
      if (value.hasValue && !completer.isCompleted && test(value.value!)) {
        completer.complete(value.value!);
      }
    },
    fireImmediately: true,
  );
  final result = await completer.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () =>
        throw TimeoutException('currentProfileProvider não emitiu'),
  );
  sub.close();
  return result;
}

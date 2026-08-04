import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/remote_source.dart';

/// Banco drift em memória, isolado por teste.
///
/// `NativeDatabase.memory()` usa a `libsqlite3` do sistema — por isso o
/// `libsqlite3-dev` é requisito para rodar os testes no desktop
/// (`sudo apt install libsqlite3-dev`).
AppDatabase createTestDatabase() {
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

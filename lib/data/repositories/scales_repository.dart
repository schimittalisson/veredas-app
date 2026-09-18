import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Repositório da tela Escalas — escrita de atribuições e dos tipos de escala.
///
/// Toda escrita passa pelo `OutboxHelper`: aplica a mudança otimista no cache
/// e enfileira na outbox. O RLS no servidor garante que só o responsável pela
/// escala (ou admin) pode escrever — um 403 reverte o cache otimista.
class ScalesRepository {
  ScalesRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // --- Scale assignments ----------------------------------------------------

  /// Cria uma atribuição de escala.
  ///
  /// A escala é da **equipe** ([memberIds] para quem tem conta, [memberNames]
  /// para quem não tem); [assigneeId]/[assigneeName] são o responsável geral,
  /// opcional. O servidor exige que ao menos um dos quatro esteja preenchido
  /// (CHECK `assignment_has_someone`).
  ///
  /// [startsOn] é guardado como DateTime à meia-noite local.
  Future<String> createAssignment({
    required String scaleTypeId,
    required DateTime startsOn,
    DateTime? endsOn,
    String? slot,
    String? task,
    String? assigneeId,
    String? assigneeName,
    List<String> memberIds = const [],
    List<String> memberNames = const [],
    String? notes,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'scale_assignments',
      rowId: id,
      payload: {
        'id': id,
        'scale_type_id': scaleTypeId,
        'starts_on': _dateOnly(startsOn),
        'ends_on': endsOn != null ? _dateOnly(endsOn) : null,
        'slot': slot,
        'task': task,
        'assignee_id': assigneeId,
        'assignee_name': assigneeName,
        'member_ids': memberIds,
        'member_names': memberNames,
        'notes': notes,
      },
      applyChange: () async {
        await _db.into(_db.scaleAssignmentRows).insertOnConflictUpdate(
              ScaleAssignmentRow(
                id: id,
                scaleTypeId: scaleTypeId,
                startsOn: _atMidnight(startsOn),
                endsOn: endsOn != null ? _atMidnight(endsOn) : null,
                slot: slot,
                task: task,
                assigneeId: assigneeId,
                assigneeName: assigneeName,
                memberIds: memberIds,
                memberNames: memberNames,
                notes: notes,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Edita uma atribuição existente.
  ///
  /// Os parâmetros de equipe substituem a lista inteira — a tela sempre manda
  /// o estado final, e não um diff.
  Future<void> updateAssignment({
    required String id,
    required String scaleTypeId,
    required DateTime startsOn,
    DateTime? endsOn,
    String? slot,
    String? task,
    String? assigneeId,
    String? assigneeName,
    List<String> memberIds = const [],
    List<String> memberNames = const [],
    String? notes,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'scale_assignments',
      rowId: id,
      payload: {
        'scale_type_id': scaleTypeId,
        'starts_on': _dateOnly(startsOn),
        'ends_on': endsOn != null ? _dateOnly(endsOn) : null,
        'slot': slot,
        'task': task,
        'assignee_id': assigneeId,
        'assignee_name': assigneeName,
        'member_ids': memberIds,
        'member_names': memberNames,
        'notes': notes,
      },
      applyChange: () async {
        // UPDATE com companion, e não `insertOnConflictUpdate` da linha
        // inteira: o upsert do drift monta os valores com
        // `toColumns(nullToAbsent: true)`, que **omite** as colunas nulas para
        // deixar o default agir. O efeito num update é que limpar um campo não
        // limpa nada — tirar o responsável geral deixaria o antigo no cache
        // até o próximo pull, e a tela mostraria alguém que já não responde
        // pela escala. No companion, `Value(null)` é presente e grava null.
        await (_db.update(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .write(
          ScaleAssignmentRowsCompanion(
            scaleTypeId: Value(scaleTypeId),
            startsOn: Value(_atMidnight(startsOn)),
            endsOn: Value(endsOn != null ? _atMidnight(endsOn) : null),
            slot: Value(slot),
            task: Value(task),
            assigneeId: Value(assigneeId),
            assigneeName: Value(assigneeName),
            memberIds: Value(memberIds),
            memberNames: Value(memberNames),
            notes: Value(notes),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove uma atribuição.
  ///
  /// No servidor vira `update deleted_at`, e não `DELETE` — quem decide isso é
  /// `SyncEntity.softDelete`, para a exclusão chegar aos outros aparelhos.
  Future<void> deleteAssignment(String id) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'scale_assignments',
      rowId: id,
      applyChange: () async {
        await (_db.delete(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  // --- Scale types (administração) ------------------------------------------
  //
  // Pela outbox, e não por RPC como as outras ações de admin: o efeito é
  // visível na hora (a barra de abas da tela Escalas sai deste cache) e
  // sobrevive a estar sem sinal na base. O RLS (`scale_types_admin_write`) é
  // quem garante que só admin escreve — um 403 reverte o cache otimista.

  /// Cria um tipo de escala. Devolve o id gerado.
  ///
  /// O `slug` é derivado do nome **uma vez, aqui**, e nunca mais muda: ele é a
  /// chave estável do tipo (é o que documenta o seed), então renomear "Almoço"
  /// para "Almoço da base" não pode mexer nele.
  Future<String> createScaleType({
    required String name,
    required String cadence,
    List<String> slots = const [],
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    final existing = await _db.select(_db.scaleTypeRows).get();
    final slug = _uniqueSlug(name, existing.map((t) => t.slug).toSet());
    // No fim da barra de abas: uma escala nova não se mete no meio das que a
    // base já usa. A ordem é editável logo depois.
    final ordering = existing.fold<int>(0, (max, t) => t.ordering > max ? t.ordering : max) + 1;

    await OutboxHelper.insert(
      db: _db,
      entity: 'scale_types',
      rowId: id,
      payload: {
        'id': id,
        'slug': slug,
        'name': name,
        'cadence': cadence,
        'slots': slots,
        'ordering': ordering,
        'is_active': true,
      },
      applyChange: () async {
        await _db.into(_db.scaleTypeRows).insertOnConflictUpdate(
              ScaleTypeRow(
                id: id,
                slug: slug,
                name: name,
                cadence: cadence,
                slots: slots,
                ordering: ordering,
                isActive: true,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Edita um tipo de escala. O `slug` e a `ordering` não entram aqui — o
  /// primeiro é imutável, a segunda tem o seu próprio caminho.
  Future<void> updateScaleType({
    required String id,
    required String name,
    required String cadence,
    required List<String> slots,
    required bool isActive,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'scale_types',
      rowId: id,
      payload: {
        'name': name,
        'cadence': cadence,
        'slots': slots,
        'is_active': isActive,
      },
      applyChange: () async {
        await (_db.update(_db.scaleTypeRows)..where((t) => t.id.equals(id)))
            .write(
          ScaleTypeRowsCompanion(
            name: Value(name),
            cadence: Value(cadence),
            slots: Value(slots),
            isActive: Value(isActive),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.scaleTypeRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove um tipo de escala (soft delete no servidor).
  ///
  /// As atribuições já montadas continuam no servidor, presas ao tipo por FK —
  /// o que some é a aba. Desativar (`is_active = false`) é o caminho para
  /// esconder sem remover.
  Future<void> deleteScaleType(String id) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'scale_types',
      rowId: id,
      payload: {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      applyChange: () async {
        await (_db.delete(_db.scaleTypeRows)..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.scaleTypeRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Reordena as abas: [orderedIds] na ordem final desejada.
  ///
  /// Uma escrita por linha que de fato mudou de posição. Arrastar um item no
  /// topo de uma lista de seis mexe em todos os seis, mas mandar as seis
  /// linhas sempre encheria a fila de updates que não mudam nada.
  Future<void> reorderScaleTypes(List<String> orderedIds) async {
    final rows = await _db.select(_db.scaleTypeRows).get();
    final byId = {for (final r in rows) r.id: r};

    for (var i = 0; i < orderedIds.length; i++) {
      final row = byId[orderedIds[i]];
      final ordering = i + 1;
      if (row == null || row.ordering == ordering) continue;

      await OutboxHelper.update(
        db: _db,
        entity: 'scale_types',
        rowId: row.id,
        payload: {'ordering': ordering},
        applyChange: () async {
          await (_db.update(_db.scaleTypeRows)
                ..where((t) => t.id.equals(row.id)))
              .write(
            ScaleTypeRowsCompanion(
              ordering: Value(ordering),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
        },
        queryExisting: () async => row.toJson(),
      );
    }
  }

  // --- Helpers --------------------------------------------------------------

  /// "Café da Manhã" -> "cafe-da-manha"; com sufixo numérico se já existir.
  ///
  /// O slug é único no servidor (índice), então uma colisão viraria erro só
  /// depois da viagem — e a linha otimista já estaria na tela. Resolver aqui
  /// custa uma consulta ao cache.
  static String _uniqueSlug(String name, Set<String> taken) {
    final base = _slugify(name);
    if (!taken.contains(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base-$i';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  static String _slugify(String name) {
    final buffer = StringBuffer();
    for (final char in name.toLowerCase().split('')) {
      final plain = _accents[char] ?? char;
      if (RegExp(r'[a-z0-9]').hasMatch(plain)) {
        buffer.write(plain);
      } else if (!buffer.toString().endsWith('-')) {
        buffer.write('-');
      }
    }
    final slug = buffer.toString().replaceAll(RegExp(r'^-+|-+$'), '');
    // Um nome só de emoji ou pontuação deixaria o slug vazio, e o servidor
    // exige um valor: o id cobre o caso sem inventar regra nova.
    return slug.isEmpty ? 'escala-${_uuid.v4().substring(0, 8)}' : slug;
  }

  /// Só as letras acentuadas do português — `unaccent` mora no servidor e não
  /// vale embarcar uma tabela Unicode inteira para gerar um slug.
  static const _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  /// Converte DateTime para string "YYYY-MM-DD" (formato `date` do PG).
  static String _dateOnly(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year.toString().padLeft(4, '0')}'
        '-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  /// DateTime à meia-noite local (para comparações por dia no cache).
  static DateTime _atMidnight(DateTime dt) {
    final d = dt.toLocal();
    return DateTime(d.year, d.month, d.day);
  }
}

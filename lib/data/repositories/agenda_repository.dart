import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Repositório da tela Agenda — escrita de eventos e slots do cronograma.
///
/// Toda escrita passa pelo `OutboxHelper`: aplica a mudança otimista no cache
/// e enfileira na outbox para envio ao servidor.
class AgendaRepository {
  AgendaRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // --- Events ---------------------------------------------------------------

  /// Cria um evento.
  Future<String> createEvent({
    required String title,
    String? description,
    required DateTime startsAt,
    DateTime? endsAt,
    bool allDay = false,
    String? location,
    String? category,
    int? colorIndex,
    String? coverImageUrl,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'events',
      rowId: id,
      payload: {
        'id': id,
        'title': title,
        'description': description,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'all_day': allDay,
        'location': location,
        'category': category,
        'color_index': colorIndex,
        'cover_image_url': coverImageUrl,
      },
      applyChange: () async {
        await _db.into(_db.eventRows).insertOnConflictUpdate(
              EventRow(
                id: id,
                title: title,
                description: description,
                startsAt: startsAt.toUtc(),
                endsAt: endsAt?.toUtc(),
                allDay: allDay,
                location: location,
                category: category,
                colorIndex: colorIndex,
                coverImageUrl: coverImageUrl,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Edita um evento existente.
  Future<void> updateEvent({
    required String id,
    required String title,
    String? description,
    required DateTime startsAt,
    DateTime? endsAt,
    bool allDay = false,
    String? location,
    String? category,
    int? colorIndex,
    String? coverImageUrl,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'events',
      rowId: id,
      payload: {
        'title': title,
        'description': description,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'all_day': allDay,
        'location': location,
        'category': category,
        'color_index': colorIndex,
        'cover_image_url': coverImageUrl,
      },
      applyChange: () async {
        final existing = await (_db.select(_db.eventRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.eventRows).insertOnConflictUpdate(
              existing.copyWith(
                title: title,
                description: Value(description),
                startsAt: startsAt.toUtc(),
                endsAt: Value(endsAt?.toUtc()),
                allDay: allDay,
                location: Value(location),
                category: Value(category),
                colorIndex: Value(colorIndex),
                coverImageUrl: Value(coverImageUrl),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.eventRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove um evento (soft delete no servidor).
  Future<void> deleteEvent(String id) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'events',
      rowId: id,
      applyChange: () async {
        await (_db.delete(_db.eventRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.eventRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  // --- Weekly slots (cronograma semanal) ------------------------------------

  /// Cria um slot do cronograma semanal.
  ///
  /// [startsAtMinutes] e [endsAtMinutes] são minutos desde meia-noite.
  /// No servidor, são colunas `time` — o payload converte para "HH:MM:SS".
  Future<String> createWeeklySlot({
    required int weekday,
    required int startsAtMinutes,
    int? endsAtMinutes,
    required String title,
    String? location,
    String? category,
    int? colorIndex,
    String? notes,
    int ordering = 0,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'weekly_slots',
      rowId: id,
      payload: {
        'id': id,
        'weekday': weekday,
        'starts_at': _minutesToTime(startsAtMinutes),
        'ends_at': endsAtMinutes != null ? _minutesToTime(endsAtMinutes) : null,
        'title': title,
        'location': location,
        'category': category,
        'color_index': colorIndex,
        'notes': notes,
        'ordering': ordering,
      },
      applyChange: () async {
        await _db.into(_db.weeklySlotRows).insertOnConflictUpdate(
              WeeklySlotRow(
                id: id,
                weekday: weekday,
                startsAtMinutes: startsAtMinutes,
                endsAtMinutes: endsAtMinutes,
                title: title,
                location: location,
                category: category,
                notes: notes,
                ordering: ordering,
                colorIndex: colorIndex,
                isActive: true,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Cria o **mesmo** slot em vários dias da semana de uma vez.
  ///
  /// Cada dia vira uma linha independente, com id próprio — e não uma linha só
  /// com uma lista de dias. Assim, editar ou apagar a terça não mexe na quinta,
  /// que é o que se espera de um cronograma: "meditação na palavra" pode mudar
  /// de horário só na sexta sem virar um caso especial no modelo.
  ///
  /// Consequência aceita: são N entradas na outbox. Como cada uma é uma linha
  /// diferente, não há conflito entre elas.
  Future<List<String>> createWeeklySlotsForWeekdays({
    required Set<int> weekdays,
    required int startsAtMinutes,
    int? endsAtMinutes,
    required String title,
    String? location,
    String? category,
    int? colorIndex,
    String? notes,
    int ordering = 0,
  }) async {
    final ids = <String>[];
    // Ordenado para as linhas nascerem na ordem da semana — o cronograma
    // agrupa por dia, e criar fora de ordem só embaralharia a outbox.
    for (final weekday in weekdays.toList()..sort()) {
      ids.add(await createWeeklySlot(
        weekday: weekday,
        startsAtMinutes: startsAtMinutes,
        endsAtMinutes: endsAtMinutes,
        title: title,
        location: location,
        category: category,
        colorIndex: colorIndex,
        notes: notes,
        ordering: ordering,
      ));
    }
    return ids;
  }

  /// Edita um slot do cronograma.
  Future<void> updateWeeklySlot({
    required String id,
    required int weekday,
    required int startsAtMinutes,
    int? endsAtMinutes,
    required String title,
    String? location,
    String? category,
    int? colorIndex,
    String? notes,
    int ordering = 0,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'weekly_slots',
      rowId: id,
      payload: {
        'weekday': weekday,
        'starts_at': _minutesToTime(startsAtMinutes),
        'ends_at': endsAtMinutes != null ? _minutesToTime(endsAtMinutes) : null,
        'title': title,
        'location': location,
        'category': category,
        'color_index': colorIndex,
        'notes': notes,
        'ordering': ordering,
      },
      applyChange: () async {
        final existing = await (_db.select(_db.weeklySlotRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.weeklySlotRows).insertOnConflictUpdate(
              existing.copyWith(
                weekday: weekday,
                startsAtMinutes: startsAtMinutes,
                endsAtMinutes: Value(endsAtMinutes),
                title: title,
                location: Value(location),
                category: Value(category),
                notes: Value(notes),
                ordering: ordering,
                colorIndex: Value(colorIndex),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.weeklySlotRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove um slot do cronograma.
  Future<void> deleteWeeklySlot(String id) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'weekly_slots',
      rowId: id,
      applyChange: () async {
        await (_db.delete(_db.weeklySlotRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.weeklySlotRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Converte minutos desde meia-noite para "HH:MM:SS" (formato `time` do PG).
  static String _minutesToTime(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}'
        ':${m.toString().padLeft(2, '0')}'
        ':00';
  }
}

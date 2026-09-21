import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/daos/documents_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Repositório do catálogo de arquivos.
///
/// Leitura devolve `Stream` do drift; escrita passa pelo `OutboxHelper`, como
/// toda escrita do app (`AGENTS.md` §6 regra 8).
///
/// **Só cadastra atalhos (`source_type = 'link'`) nesta versão.** A tabela já
/// aceita `'file'` com `storage_path`, mas o app ainda não sobe arquivo — ver o
/// comentário da migration `20260828000100_documents.sql`.
class DocumentsRepository {
  DocumentsRepository(this._db) : _dao = DocumentsDao(_db);

  final AppDatabase _db;
  final DocumentsDao _dao;
  static const _uuid = Uuid();

  Stream<List<DocumentRow>> watchDocuments(DocumentSort sort) =>
      _dao.watchDocuments(sort);

  /// Cria um atalho. O id é gerado no cliente (UUID v4), como nas outras
  /// entidades — é o que permite a escrita otimista antes de falar com o
  /// servidor.
  Future<String> createLink({
    required String title,
    required String url,
    String? description,
    String? createdBy,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'documents',
      rowId: id,
      payload: {
        'id': id,
        'title': title,
        'description': description,
        'source_type': 'link',
        'url': url,
        // created_by fica para o servidor: mandar do cliente permitiria forjar
        // a autoria, e a coluna é só informativa.
      },
      applyChange: () async {
        await _dao.upsertDocument(
          DocumentRow(
            id: id,
            title: title,
            description: description,
            sourceType: 'link',
            url: url,
            createdBy: createdBy,
            createdAt: now,
            updatedAt: now,
          ),
        );
      },
    );

    return id;
  }

  Future<void> updateLink({
    required String id,
    required String title,
    required String url,
    String? description,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'documents',
      rowId: id,
      payload: {
        'title': title,
        'description': description,
        'source_type': 'link',
        'url': url,
      },
      applyChange: () async {
        final existing = await _dao.findById(id);
        if (existing == null) return;

        await _dao.upsertDocument(
          existing.copyWith(
            title: title,
            description: Value(description),
            sourceType: 'link',
            url: Value(url),
            // O `updatedAt` otimista é o que faz a linha subir na ordenação
            // "alterados recentemente" antes do servidor confirmar. O trigger
            // `documents_touch_updated_at` sobrescreve com a hora do servidor
            // no próximo pull.
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      },
      queryExisting: () async => (await _dao.findById(id))?.toJson(),
    );
  }

  /// Remove um atalho.
  ///
  /// **É um UPDATE de `deleted_at`, não um DELETE.** Com o soft delete, um
  /// admin ainda consegue recuperar o item pelo SQL Editor, e o item
  /// desaparece para todos no próximo pull — que é `fullReplace`, então o
  /// cache local é reconstruído sem ele.
  ///
  /// A operação vai para a outbox como `update` explícito. Quando isto foi
  /// escrito era a única forma: o `OutboxHelper.delete` mandava um DELETE
  /// físico. Hoje o `OutboxWorker` faz soft delete sozinho em toda entidade
  /// com `softDelete: true` (o caso desta), então os dois caminhos chegam ao
  /// mesmo lugar — este continua aqui por ser o explícito.
  ///
  /// Localmente a linha é removida na hora, porque o cache não guarda
  /// `deleted_at` (ver `tables.dart`). **Quem garante que ela não volta pelo
  /// pull é o filtro de lápide em `SyncService._doPull`** — a policy de
  /// leitura não basta, porque a policy de escrita do admin é `for all` e o
  /// `using` dela também libera o SELECT da linha apagada.
  Future<void> deleteDocument(String id) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'documents',
      rowId: id,
      payload: {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      applyChange: () async => _dao.removeDocument(id),
      queryExisting: () async => (await _dao.findById(id))?.toJson(),
    );
  }
}

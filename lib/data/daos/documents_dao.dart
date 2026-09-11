import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// Como a lista de arquivos é ordenada.
///
/// A ordenação é escolha do usuário e não do admin: o mesmo catálogo serve para
/// "qual foi o material novo?" (recentes) e "onde está o manual X?"
/// (alfabética), e não existe uma ordem única que atenda os dois.
enum DocumentSort {
  /// Alterados por último primeiro. É o padrão: responde "o que mudou?".
  recentlyUpdated,

  /// Adicionados por último primeiro.
  recentlyAdded,

  /// Título de A a Z.
  titleAsc,

  /// Título de Z a A.
  titleDesc,
}

/// Leitura e escrita local do catálogo de arquivos.
class DocumentsDao {
  DocumentsDao(this.db);

  final AppDatabase db;

  /// Observa o catálogo na ordem pedida.
  ///
  /// Trocar a ordenação recria o stream, o que é aceitável: a tabela tem
  /// dezenas de linhas, não milhares. Ordenar no SQL em vez de no Dart mantém a
  /// UI burra e deixa a decisão num só lugar.
  Stream<List<DocumentRow>> watchDocuments(DocumentSort sort) {
    final query = db.select(db.documentRows);

    // O `title` entra como critério de desempate nas ordens por data: sem ele,
    // dois documentos com o mesmo instante (um seed, por exemplo) alternariam
    // de posição entre rebuilds.
    switch (sort) {
      case DocumentSort.recentlyUpdated:
        query.orderBy([
          (t) => OrderingTerm.desc(t.updatedAt),
          (t) => OrderingTerm.asc(t.title),
        ]);
      case DocumentSort.recentlyAdded:
        query.orderBy([
          (t) => OrderingTerm.desc(t.createdAt),
          (t) => OrderingTerm.asc(t.title),
        ]);
      case DocumentSort.titleAsc:
        query.orderBy([(t) => OrderingTerm.asc(t.title)]);
      case DocumentSort.titleDesc:
        query.orderBy([(t) => OrderingTerm.desc(t.title)]);
    }

    return query.watch();
  }

  Future<DocumentRow?> findById(String id) {
    return (db.select(db.documentRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertDocument(DocumentRow row) {
    return db.into(db.documentRows).insertOnConflictUpdate(row);
  }

  Future<void> removeDocument(String id) {
    return (db.delete(db.documentRows)..where((t) => t.id.equals(id))).go();
  }
}

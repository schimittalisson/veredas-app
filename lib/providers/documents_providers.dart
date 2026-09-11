import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/daos/documents_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da aba Arquivos.

/// Ordenação escolhida pelo usuário.
///
/// Vive num `Notifier` e não num parâmetro da tela para sobreviver à troca de
/// aba: o `indexedStack` mantém a tela viva, mas o estado de ordenação precisa
/// existir mesmo se a árvore for reconstruída.
///
/// O padrão é "alterados recentemente" porque a pergunta mais comum ao abrir a
/// aba é "tem material novo?".
class DocumentSortNotifier extends Notifier<DocumentSort> {
  @override
  DocumentSort build() => DocumentSort.recentlyUpdated;

  void set(DocumentSort sort) => state = sort;
}

final documentSortProvider =
    NotifierProvider<DocumentSortNotifier, DocumentSort>(
  DocumentSortNotifier.new,
);

/// O catálogo, na ordem escolhida.
///
/// Observa `documentSortProvider`: trocar a ordenação recria o stream do drift
/// com outro `ORDER BY`. A ordenação acontece no SQLite, não no Dart.
final documentsProvider = StreamProvider<List<DocumentRow>>((ref) {
  final sort = ref.watch(documentSortProvider);
  return ref.watch(documentsRepositoryProvider).watchDocuments(sort);
});

/// Um documento específico, para o editor carregar o estado inicial.
final documentByIdProvider = Provider.family<DocumentRow?, String>((ref, id) {
  final docs = ref.watch(documentsProvider).value ?? const [];
  return docs.where((d) => d.id == id).firstOrNull;
});

/// Ações de escrita. Só admin chega aqui — a tela esconde os botões e a policy
/// `documents_admin_write` recusa no servidor de qualquer forma.
class DocumentActions extends Notifier<void> {
  @override
  void build() {}

  Future<String> createLink({
    required String title,
    required String url,
    String? description,
  }) {
    return ref.read(documentsRepositoryProvider).createLink(
          title: title,
          url: url,
          description: description,
          createdBy: ref.read(currentUserIdProvider),
        );
  }

  Future<void> updateLink({
    required String id,
    required String title,
    required String url,
    String? description,
  }) {
    return ref.read(documentsRepositoryProvider).updateLink(
          id: id,
          title: title,
          url: url,
          description: description,
        );
  }

  Future<void> delete(String id) {
    return ref.read(documentsRepositoryProvider).deleteDocument(id);
  }
}

final documentActionsProvider =
    NotifierProvider<DocumentActions, void>(DocumentActions.new);

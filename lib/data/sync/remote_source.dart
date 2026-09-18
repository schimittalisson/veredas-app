import 'package:supabase_flutter/supabase_flutter.dart';

/// Fonte remota abstrata para sincronização.
///
/// O `SyncService` e o `OutboxWorker` dependem desta interface, não do
/// `SupabaseClient` diretamente. Isto segue o padrão do `docs/PLANO.md §2.4`
/// ("cada fonte remota fica atrás de uma interface abstrata") e torna os
/// testes viáveis sem rede: uma `FakeRemoteSource` retorna dados
/// pré-configurados.
///
/// Os métodos devolvem `List<Map<String, dynamic>>` no formato do PostgREST
/// (snake_case, ISO strings) — o mesmo que `supabase.from(t).select()`.
abstract class RemoteSource {
  /// Consulta linhas de uma tabela/view.
  ///
  /// Se [gtColumn] e [gtValue] forem fornecidos, filtra `gtColumn > gtValue`.
  /// Se [orderColumn] for fornecido, ordena asc por essa coluna.
  Future<List<Map<String, dynamic>>> fetch({
    required String table,
    String? gtColumn,
    Object? gtValue,
    String? orderColumn,
  });

  /// Insere uma linha. Lança `PostgrestException` em conflito (23505) ou
  /// violação de RLS (42501).
  Future<void> insert({
    required String table,
    required Map<String, dynamic> payload,
  });

  /// Atualiza linhas onde `eqColumn == eqValue`. Devolve as linhas afetadas
  /// — lista vazia significa 0 linhas (linha sumiu ou RLS filtrou).
  Future<List<Map<String, dynamic>>> update({
    required String table,
    required Map<String, dynamic> payload,
    required String eqColumn,
    required Object eqValue,
  });

  /// Apaga linhas onde `eqColumn == eqValue`. Devolve as linhas apagadas
  /// — lista vazia significa 0 linhas.
  Future<List<Map<String, dynamic>>> delete({
    required String table,
    required String eqColumn,
    required Object eqValue,
  });
}

/// Implementação de [RemoteSource] sobre o `SupabaseClient`.
class SupabaseRemoteSource implements RemoteSource {
  SupabaseRemoteSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetch({
    required String table,
    String? gtColumn,
    Object? gtValue,
    String? orderColumn,
  }) async {
    // Os builders do supabase_flutter têm tipos diferentes a cada chamada
    // (PostgrestFilterBuilder, PostgrestTransformBuilder...), então a cadeia
    // é montada com `dynamic` e resolvida no `await`.
    dynamic query = _client.from(table).select();
    if (gtColumn != null && gtValue != null) {
      query = query.gt(gtColumn, gtValue);
    }
    if (orderColumn != null) {
      query = query.order(orderColumn);
    }
    final result = await query;
    return (result as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<void> insert({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    await _client.from(table).insert(payload);
  }

  @override
  Future<List<Map<String, dynamic>>> update({
    required String table,
    required Map<String, dynamic> payload,
    required String eqColumn,
    required Object eqValue,
  }) async {
    return _client
        .from(table)
        .update(payload)
        .eq(eqColumn, eqValue)
        .select();
  }

  @override
  Future<List<Map<String, dynamic>>> delete({
    required String table,
    required String eqColumn,
    required Object eqValue,
  }) async {
    return _client.from(table).delete().eq(eqColumn, eqValue).select();
  }
}

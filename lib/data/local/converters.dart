import 'dart:convert';

import 'package:drift/drift.dart';

/// `text[]` do Postgres (ex.: `scale_types.slots`) guardado como JSON no SQLite.
///
/// SQLite não tem tipo array. JSON é preferível a um separador (`,` ou `|`)
/// porque os valores vêm do usuário — um slot chamado "06:00-07:00, extra"
/// corromperia um split por vírgula em silêncio.
class StringListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter2<List<String>, String, List<dynamic>> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) return const [];
    return decoded.map((e) => e.toString()).toList(growable: false);
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);

  @override
  List<String> fromJson(List<dynamic> json) =>
      json.map((e) => e.toString()).toList(growable: false);

  @override
  List<dynamic> toJson(List<String> value) => value;
}

import 'package:drift/native.dart';

import 'package:veredas/data/local/app_database.dart';

/// Banco drift em memória, isolado por teste.
///
/// `NativeDatabase.memory()` usa a `libsqlite3` do sistema — por isso o
/// `libsqlite3-dev` é requisito para rodar os testes no desktop
/// (`sudo apt install libsqlite3-dev`).
AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

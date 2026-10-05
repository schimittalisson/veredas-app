import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/l10n/app_localizations.dart';

/// Nome do papel para exibir. Um `switch` exaustivo: um papel novo no enum
/// deixa de compilar aqui em vez de aparecer como "Obreiro" nas telas de
/// Membros e Convites.
String roleLabel(AppLocalizations l, AppRole role) => switch (role) {
      AppRole.admin => l.admin_role_admin,
      AppRole.obreiro => l.admin_role_obreiro,
      AppRole.aluno => l.admin_role_aluno,
    };

import 'package:flutter/material.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_typography.dart';

/// Ilha de Material dentro do app Cupertino.
///
/// O app roda sobre `CupertinoApp`, onde não existe ancestral `Material`.
/// Um único widget ainda precisa dele: o `TableCalendar` do pacote
/// `table_calendar`, que usa `InkWell` internamente e não tem equivalente
/// Cupertino. Sem um `Material` acima, ele lança "No Material widget found".
///
/// Durante a migração este widget era aplicado globalmente, no `builder` do
/// `CupertinoApp`, para que as telas ainda não convertidas continuassem
/// funcionando. Agora que todas migraram, ele foi reduzido ao seu escopo real:
/// envolve só o calendário. O resto da árvore é Cupertino puro.
///
/// Fornece duas coisas:
/// - um `Material` transparente, que satisfaz o requisito de ancestral sem
///   pintar nada por cima do fundo do `CupertinoPageScaffold`;
/// - um `Theme` derivado da nossa paleta, porque o `TableCalendar` chama
///   `Theme.of` — sem ele, cairia no `ThemeData.fallback()`, que é azul e
///   ignora o tema escuro.
///
/// Some junto com a dependência, no dia em que houver um calendário Cupertino
/// ou um construído em casa.
class MaterialCompat extends StatelessWidget {
  const MaterialCompat({
    required this.colors,
    required this.brightness,
    required this.child,
    super.key,
  });

  final AppColors colors;
  final Brightness brightness;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _themeData(),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }

  ThemeData _themeData() {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.tint,
      onPrimary: colors.onTint,
      primaryContainer: colors.tintContainer,
      onPrimaryContainer: colors.onTintContainer,
      secondary: colors.tint,
      onSecondary: colors.onTint,
      secondaryContainer: colors.tintContainer,
      onSecondaryContainer: colors.onTintContainer,
      error: colors.destructive,
      onError: colors.onDestructive,
      surface: colors.surface,
      onSurface: colors.label,
      onSurfaceVariant: colors.secondaryLabel,
      outline: colors.separator,
      outlineVariant: colors.separator,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge: AppTypography.title.copyWith(color: colors.label),
        titleMedium: AppTypography.headline.copyWith(color: colors.label),
        bodyLarge: AppTypography.body.copyWith(color: colors.label),
        bodyMedium: AppTypography.subheadline.copyWith(color: colors.label),
        bodySmall: AppTypography.footnote.copyWith(color: colors.secondaryLabel),
      ),
    );
  }
}

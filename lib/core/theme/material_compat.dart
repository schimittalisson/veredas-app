import 'package:flutter/material.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_typography.dart';

/// **Andaime temporário da migração para Cupertino. Apagar na Fase 11.**
///
/// Sob `CupertinoApp` não existe ancestral `Material`, e boa parte dos widgets
/// do Material (`Card`, `ListTile`, `TextFormField`, `InkWell`…) lança
/// "No Material widget found" sem ele. Como as 29 telas migram em fases, elas
/// precisam continuar funcionando enquanto ainda usam Material.
///
/// Este widget fornece o que falta:
/// - um `Theme` derivado da nossa paleta, para que os `Theme.of(context)` que
///   ainda existem devolvam cores coerentes em vez do `ThemeData.fallback()`
///   (que é azul e ignora o tema escuro);
/// - um `Material` transparente, que satisfaz o requisito de ancestral sem
///   pintar nada por cima do fundo do `CupertinoPageScaffold`.
///
/// Quando a última tela deixar de importar `material.dart`, este arquivo sai
/// junto com a dependência — é justamente por isso que ele mora sozinho aqui,
/// e não escondido dentro do `app.dart`.
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
      // `type: transparency` evita que este Material pinte um fundo opaco:
      // quem manda no fundo é o CupertinoPageScaffold de cada tela.
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
      surface: colors.groupedBackground,
      onSurface: colors.label,
      onSurfaceVariant: colors.secondaryLabel,
      outline: colors.separator,
      outlineVariant: colors.separator,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: colors.groupedBackground,
      // Alinha os poucos estilos que destoariam demais do Cupertino enquanto
      // a tela ainda não migrou. Não vale detalhar mais: é código com data
      // de validade.
      textTheme: base.textTheme.copyWith(
        titleLarge: AppTypography.title.copyWith(color: colors.label),
        titleMedium: AppTypography.headline.copyWith(color: colors.label),
        titleSmall: AppTypography.subheadlineEmphasis.copyWith(color: colors.label),
        bodyLarge: AppTypography.body.copyWith(color: colors.label),
        bodyMedium: AppTypography.subheadline.copyWith(color: colors.label),
        bodySmall: AppTypography.footnote.copyWith(color: colors.secondaryLabel),
        labelMedium: AppTypography.footnoteEmphasis.copyWith(color: colors.label),
        labelSmall: AppTypography.caption.copyWith(color: colors.secondaryLabel),
      ),
      dividerTheme: DividerThemeData(
        color: colors.separator,
        thickness: 0.5,
        space: 0.5,
      ),
    );
  }
}

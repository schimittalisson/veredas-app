import 'package:flutter/cupertino.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_typography.dart';

/// Entrega [AppColors] à árvore de widgets.
///
/// Não usa `ThemeExtension` porque `ThemeExtension` vive no Material e o app
/// roda sobre `CupertinoApp`. Um `InheritedWidget` próprio resolve o mesmo
/// problema sem arrastar o Material junto.
///
/// A tipografia não passa por aqui: [AppTypography] é toda `static const`,
/// não varia com o brilho, então não há motivo para custar uma dependência de
/// contexto em cada widget que só quer um tamanho de fonte.
class AppTheme extends InheritedWidget {
  const AppTheme({
    required this.colors,
    required super.child,
    super.key,
  });

  final AppColors colors;

  /// Cores do tema ativo. Lance se não houver [AppTheme] acima — é erro de
  /// montagem, não um caso a tratar em runtime.
  static AppColors of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(theme != null, 'Nenhum AppTheme encontrado acima deste widget.');
    return theme!.colors;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) => colors != oldWidget.colors;
}

/// Açúcar sintático: `context.colors.tint` em vez de `AppTheme.of(context)`.
///
/// Substitui o antigo `Theme.of(context).colorScheme` — mais curto, e sem
/// acoplar a tela ao design system.
extension AppThemeX on BuildContext {
  AppColors get colors => AppTheme.of(this);
}

/// Constrói o [CupertinoThemeData] a partir da nossa paleta.
///
/// Os widgets Cupertino leem daqui (a cor do `CupertinoButton`, do cursor de
/// texto, do indicador de atividade). Manter essa derivação num único lugar é
/// o que impede o tema nativo e o nosso de divergirem.
CupertinoThemeData cupertinoThemeFor(AppColors colors, Brightness brightness) {
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: colors.tint,
    primaryContrastingColor: colors.onTint,
    scaffoldBackgroundColor: colors.groupedBackground,
    barBackgroundColor: colors.elevatedSurface,
    // applyThemeToAll faz o tema alcançar também os widgets que, por padrão,
    // ignoram o CupertinoTheme (CupertinoButton entre eles). Sem isto, botões
    // apareceriam no azul do sistema em vez do marrom da marca.
    applyThemeToAll: true,
    textTheme: CupertinoTextThemeData(
      primaryColor: colors.tint,
      textStyle: AppTypography.body.copyWith(color: colors.label),
      actionTextStyle: AppTypography.body.copyWith(color: colors.tint),
      navTitleTextStyle: AppTypography.navTitle.copyWith(color: colors.label),
      navLargeTitleTextStyle:
          AppTypography.largeTitle.copyWith(color: colors.label),
      tabLabelTextStyle: AppTypography.caption2,
      pickerTextStyle: AppTypography.body.copyWith(color: colors.label),
      dateTimePickerTextStyle:
          AppTypography.body.copyWith(color: colors.label),
    ),
  );
}

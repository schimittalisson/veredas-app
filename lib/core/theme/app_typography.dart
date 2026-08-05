import 'package:flutter/painting.dart';

/// Escala tipográfica do app, na régua do iOS.
///
/// Substitui o `TextTheme` do Material, que não existe no Cupertino. Os nomes
/// vêm do *Human Interface Guidelines* da Apple (`title`, `headline`, `body`,
/// `footnote`, `caption`) porque os tamanhos seguem aquela escala — o Material
/// usa outra (`titleMedium` é 16, o `headline` do iOS é 17).
///
/// **`fontFamily` é deliberadamente nulo.** O `Text` faz merge do estilo
/// recebido sobre o `DefaultTextStyle`, então a família vem do
/// `CupertinoTheme` — `.SF Pro Text` no iOS, com fallback para a fonte do
/// sistema no Android. Fixar a família aqui quebraria esse fallback.
///
/// O `letterSpacing` negativo nos tamanhos grandes imita o *tracking* que a
/// Apple aplica no SF Pro Display: sem ele, títulos em SF ficam frouxos.
class AppTypography {
  const AppTypography._();

  /// 28/34 — título de tela grande (`largeTitle` do iOS).
  static const TextStyle largeTitle = TextStyle(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// 22/28 — título de seção proeminente.
  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  /// 20/25 — título da barra de navegação.
  static const TextStyle navTitle = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  /// 17/22 — texto em destaque dentro de uma célula (`headline`).
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  /// 17/22 — corpo padrão. É o tamanho de leitura do iOS.
  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.4,
  );

  /// 15/20 — corpo secundário (`subheadline`).
  static const TextStyle subheadline = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
  );

  /// 15/20 — [subheadline] com peso, para rótulos de célula.
  static const TextStyle subheadlineEmphasis = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// 13/18 — legendas e timestamps (`footnote`).
  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  /// 13/18 — [footnote] com peso.
  static const TextStyle footnoteEmphasis = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );

  /// 12/16 — rótulo de tabela, cabeçalho de coluna (`caption1`).
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  /// 11/13 — o menor texto legível (`caption2`). Rótulo da tab bar.
  static const TextStyle caption2 = TextStyle(
    fontSize: 11,
    height: 13 / 11,
    fontWeight: FontWeight.w500,
  );

  /// Cabeçalho de seção de lista agrupada: maiúsculas, pequeno e espaçado.
  /// É a assinatura visual das listas de Ajustes do iOS.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );
}

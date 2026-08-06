import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

/// Paleta extraída da logo da base (o vitral).
///
/// Valores amostrados de `assets/images/logo.jpg`, não estimados a olho.
class VeredasPalette {
  const VeredasPalette._();

  /// Traço e tipografia da logo. É a cor de marca (`primary` no claro).
  static const Color brown = Color(0xFF62503F);

  /// Fundo do vitral. Mais quente que branco puro e coerente com a identidade.
  static const Color cream = Color(0xFFF5EEE6);

  // As 5 cores do vitral, na ordem em que aparecem na logo.
  static const Color teal = Color(0xFF3CAC9E);
  static const Color blue = Color(0xFF619CD4);
  static const Color orange = Color(0xFFED7050);
  static const Color yellow = Color(0xFFFCC64C);
  static const Color purple = Color(0xFF904195);
}

/// Cores semânticas do app, **independentes de Material e de Cupertino**.
///
/// Antes a UI lia `Theme.of(context).colorScheme.*`, o que amarrava 65 pontos
/// do código ao Material. O `CupertinoThemeData` não tem `ColorScheme` — não
/// existe `onSurfaceVariant` nem `primaryContainer` no mundo Cupertino. Em vez
/// de espalhar `CupertinoColors` cru pelas telas (perdendo a identidade visual
/// e o suporte a tema escuro), a UI passa a ler daqui via `context.colors`.
///
/// O benefício é que a camada de widgets não sabe qual design system está por
/// baixo: trocar de novo no futuro não toca nas telas.
///
/// Os nomes seguem a estrutura do iOS (`label`, `secondaryLabel`, `separator`,
/// `groupedBackground`) porque é para lá que o app está indo, mas os valores
/// mantêm a temperatura da marca.
@immutable
class AppColors {
  const AppColors({
    required this.groupedBackground,
    required this.surface,
    required this.elevatedSurface,
    required this.fill,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.tint,
    required this.onTint,
    required this.tintContainer,
    required this.onTintContainer,
    required this.separator,
    required this.destructive,
    required this.onDestructive,
    required this.success,
    required this.warning,
    required this.pendingSync,
    required this.accents,
    required this.accentContainers,
    required this.onAccentContainers,
  });

  // --- Superfícies ----------------------------------------------------------

  /// Fundo das telas com listas agrupadas — o cinza por trás dos cartões.
  /// Equivale a `systemGroupedBackground` do iOS.
  final Color groupedBackground;

  /// Fundo de cartões e células sobre [groupedBackground].
  final Color surface;

  /// Superfícies que precisam se destacar de [surface] (barras, cabeçalhos).
  final Color elevatedSurface;

  /// Fundo de campos de texto e chips. `tertiarySystemFill` do iOS.
  final Color fill;

  // --- Texto ----------------------------------------------------------------

  /// Texto principal.
  final Color label;

  /// Texto de apoio: legendas, timestamps, subtítulos.
  final Color secondaryLabel;

  /// Texto desabilitado e placeholders.
  final Color tertiaryLabel;

  // --- Marca ----------------------------------------------------------------

  /// Cor de destaque do app (botões, links, ícone da tab ativa).
  final Color tint;

  /// Texto sobre [tint].
  final Color onTint;

  /// Fundo suave da marca, para destaques que não são botões.
  final Color tintContainer;

  /// Texto sobre [tintContainer].
  final Color onTintContainer;

  // --- Estrutura e estado ---------------------------------------------------

  /// Divisórias e bordas de célula.
  final Color separator;

  /// Ações destrutivas e mensagens de erro.
  final Color destructive;

  final Color onDestructive;

  /// Badge "Respondido" no mural de oração.
  final Color success;

  final Color warning;

  /// Itens da outbox aguardando envio ("enviando…").
  final Color pendingSync;

  // --- Acentos do vitral ----------------------------------------------------

  /// Cores vivas, para bordas, ícones e marcadores de calendário.
  final List<Color> accents;

  /// Fundos legíveis correspondentes a [accents], mesmo índice.
  ///
  /// A separação existe por acessibilidade: o amarelo e o laranja da logo têm
  /// contraste insuficiente para texto quando usados como fundo. Use sempre
  /// `accentContainer` atrás de texto e `accent` só para traços e ícones.
  final List<Color> accentContainers;

  /// Cor de texto sobre [accentContainers], mesmo índice.
  final List<Color> onAccentContainers;

  /// Acento estável para uma entidade, derivado de uma chave.
  ///
  /// Recebe o `slug` do tipo de escala ou a `category` do evento — assim a cor
  /// de "Servir ao Todo" é sempre a mesma, em qualquer dispositivo, **sem
  /// precisar de uma coluna de cor no banco**. Usar o índice da lista em vez
  /// disso faria a cor mudar quando um tipo novo fosse inserido no meio.
  Color accentFor(String key) => accents[_indexFor(key)];
  Color accentContainerFor(String key) => accentContainers[_indexFor(key)];
  Color onAccentContainerFor(String key) => onAccentContainers[_indexFor(key)];

  int _indexFor(String key) {
    if (key.isEmpty) return 0;
    // hashCode do Dart não é estável entre execuções (varia com o hash seed),
    // então uma soma de code units é o que garante a mesma cor sempre.
    var sum = 0;
    for (final unit in key.codeUnits) {
      sum = (sum + unit) % accents.length;
    }
    return sum;
  }

  /// Tema claro: cartões brancos sobre o creme da logo — a estrutura de lista
  /// agrupada do iOS, com a temperatura da marca no lugar do cinza neutro.
  static const AppColors light = AppColors(
    groupedBackground: VeredasPalette.cream,
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFFBF7F2),
    fill: Color(0xFFEAE2D8),
    label: Color(0xFF1C1712),
    secondaryLabel: Color(0xFF6B5F52),
    tertiaryLabel: Color(0xFF9C9084),
    tint: VeredasPalette.brown,
    onTint: Color(0xFFFFFFFF),
    tintContainer: Color(0xFFE4D8CB),
    onTintContainer: Color(0xFF2A211A),
    separator: Color(0xFFD8CEC2),
    destructive: Color(0xFFD0342C),
    onDestructive: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D4F),
    warning: Color(0xFF9A6B00),
    pendingSync: Color(0xFF7A6A5C),
    // 10 acentos: os 5 do vitral mais 5 harmonizados na mesma tonalidade.
    // Cinco cores não bastavam — com 6 categorias em uso, três caíam no mesmo
    // amarelo, e a cor deixava de distinguir o que deveria distinguir.
    accents: [
      VeredasPalette.teal,
      VeredasPalette.blue,
      VeredasPalette.orange,
      VeredasPalette.yellow,
      VeredasPalette.purple,
      Color(0xFF6FB86A), // verde
      Color(0xFFE27BA8), // rosa
      Color(0xFF7B7FD4), // índigo
      Color(0xFFC4703F), // terracota
      Color(0xFF4FB3C4), // ciano
    ],
    // Cada acento misturado a 18% sobre o creme. Os pares abaixo foram
    // verificados em >= 4.5:1 (WCAG AA para texto normal), não estimados.
    accentContainers: [
      Color(0xFFD4E2D9),
      Color(0xFFDADFE3),
      Color(0xFFF4D7CB),
      Color(0xFFF6E7CA),
      Color(0xFFE3CFD7),
      Color(0xFFDCE7D2),
      Color(0xFFF3D9E3),
      Color(0xFFDCDCEF),
      Color(0xFFEEDCCF),
      Color(0xFFD2E5E9),
    ],
    onAccentContainers: [
      Color(0xFF266C64), // 4.60:1
      Color(0xFF3F658A), // 4.55:1
      Color(0xFF9A4934), // 4.57:1
      Color(0xFF7E6326), // 4.65:1
      Color(0xFF893E8E), // 4.51:1
      Color(0xFF3F6B37), // 4.87:1
      Color(0xFF9B3F63), // 4.82:1
      Color(0xFF4A4E96), // 5.50:1
      Color(0xFF8A4A25), // 5.11:1
      Color(0xFF2A6C77), // 4.59:1
    ],
  );

  /// Tema escuro: preto quente, como o `systemBackground` escuro do iOS, mas
  /// puxado para o marrom da marca em vez do cinza neutro.
  ///
  /// Os acentos são clareados e os contêineres escurecidos — inverter a
  /// luminosidade é o que mantém o contraste do texto em ambos os temas.
  static const AppColors dark = AppColors(
    groupedBackground: Color(0xFF17130F),
    surface: Color(0xFF221C17),
    elevatedSurface: Color(0xFF2C2520),
    fill: Color(0xFF332B24),
    label: Color(0xFFF2EBE3),
    secondaryLabel: Color(0xFFB3A697),
    tertiaryLabel: Color(0xFF7D7266),
    tint: Color(0xFFD8C3AC),
    onTint: Color(0xFF33271C),
    tintContainer: Color(0xFF3D3128),
    onTintContainer: Color(0xFFEFE2D4),
    separator: Color(0xFF38302A),
    destructive: Color(0xFFFF6961),
    onDestructive: Color(0xFF3A0C08),
    success: Color(0xFF7BC894),
    warning: Color(0xFFE8BC5A),
    pendingSync: Color(0xFFBFAE9E),
    accents: [
      Color(0xFF64D0C2),
      Color(0xFF8EC5FA),
      Color(0xFFFF9378),
      Color(0xFFFFD371),
      Color(0xFFB365B7),
      Color(0xFF8FD98A), // verde
      Color(0xFFF09BC0), // rosa
      Color(0xFFA0A3E8), // índigo
      Color(0xFFE0996B), // terracota
      Color(0xFF74CBD9), // ciano
    ],
    accentContainers: [
      Color(0xFF26443D),
      Color(0xFF31404E),
      Color(0xFF5B3226),
      Color(0xFF604C25),
      Color(0xFF40243B),
      Color(0xFF2C4429),
      Color(0xFF4E2B3B),
      Color(0xFF33355C),
      Color(0xFF4A2E1C),
      Color(0xFF22454C),
    ],
    onAccentContainers: [
      Color(0xFF52BAAD), // 4.55:1
      Color(0xFF7BAEDD), // 4.53:1
      Color(0xFFF28D73), // 4.58:1
      Color(0xFFFCC64C), // 5.21:1
      Color(0xFFBF7EC4), // 4.56:1
      Color(0xFF7FC97A), // 5.36:1
      Color(0xFFE68CB2), // 5.06:1
      Color(0xFF9EA1E4), // 4.81:1
      Color(0xFFD89463), // 4.91:1
      Color(0xFF63C0CF), // 4.93:1
    ],
  );
}

import 'package:flutter/material.dart';

/// Paleta extraída da logo da base (o vitral).
///
/// O `ColorScheme` do Material 3 é gerado a partir de uma única cor semente
/// (o marrom do traço da logo), o que dá uma base neutra e sóbria. Estas cores
/// vivem fora dele porque têm significado **semântico**, não decorativo: cada
/// uma identifica um tipo de escala ou uma categoria de evento.
///
/// O ganho é funcional, não estético — na grade do cronograma e nas abas de
/// escala o obreiro reconhece a categoria pela cor antes de ler o texto.
class VeredasPalette {
  const VeredasPalette._();

  // Valores amostrados de assets/images/logo.jpg, não estimados a olho.

  /// Traço e tipografia da logo. Cor semente do `ColorScheme`.
  static const Color brown = Color(0xFF62503F);

  /// Fundo do vitral. Usada como `surface` no tema claro — mais quente que
  /// branco puro e coerente com a identidade da base.
  static const Color cream = Color(0xFFF5EEE6);

  // As 5 cores do vitral, na ordem em que aparecem na logo.
  static const Color teal = Color(0xFF3CAC9E);
  static const Color blue = Color(0xFF619CD4);
  static const Color orange = Color(0xFFED7050);
  static const Color yellow = Color(0xFFFCC64C);
  static const Color purple = Color(0xFF904195);
}

/// Cores de acento que não cabem no `ColorScheme`.
///
/// Cada acento vem em par: [accents] é a cor viva (bordas, ícones, marcadores)
/// e [accentContainers] é a versão dessaturada para **fundos**.
///
/// A separação existe por acessibilidade: o amarelo e o laranja da logo têm
/// contraste insuficiente para texto quando usados como fundo. Pintar uma
/// célula da grade com `yellow` puro e escrever em cima dela reprova em
/// WCAG AA. Use sempre `accentContainer` atrás de texto e `accent` só para
/// traços e ícones.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.accents,
    required this.accentContainers,
    required this.onAccentContainers,
    required this.success,
    required this.warning,
    required this.pendingSync,
  });

  /// Cores vivas, para bordas, ícones e marcadores de calendário.
  final List<Color> accents;

  /// Fundos legíveis correspondentes a [accents], mesmo índice.
  final List<Color> accentContainers;

  /// Cor de texto sobre [accentContainers], mesmo índice.
  final List<Color> onAccentContainers;

  /// Badge "Respondido" no mural de oração.
  final Color success;

  final Color warning;

  /// Itens da outbox aguardando envio ("enviando…").
  final Color pendingSync;

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

  static const AppColors light = AppColors(
    accents: [
      VeredasPalette.teal,
      VeredasPalette.blue,
      VeredasPalette.orange,
      VeredasPalette.yellow,
      VeredasPalette.purple,
    ],
    // Cada acento misturado a 18% sobre o creme. Os pares abaixo foram
    // verificados em >= 4.5:1 (WCAG AA para texto normal), não estimados.
    accentContainers: [
      Color(0xFFD4E2D9),
      Color(0xFFDADFE3),
      Color(0xFFF4D7CB),
      Color(0xFFF6E7CA),
      Color(0xFFE3CFD7),
    ],
    onAccentContainers: [
      Color(0xFF266C64), // 4.60:1
      Color(0xFF3F658A), // 4.55:1
      Color(0xFF9A4934), // 4.57:1
      Color(0xFF7E6326), // 4.65:1
      Color(0xFF893E8E), // 4.51:1
    ],
    success: Color(0xFF2E7D4F),
    warning: Color(0xFF9A6B00),
    pendingSync: Color(0xFF7A6A5C),
  );

  /// No escuro os acentos são clareados e os contêineres escurecidos — inverter
  /// a luminosidade é o que mantém o contraste do texto em ambos os temas.
  static const AppColors dark = AppColors(
    accents: [
      Color(0xFF64D0C2),
      Color(0xFF8EC5FA),
      Color(0xFFFF9378),
      Color(0xFFFFD371),
      Color(0xFFB365B7),
    ],
    accentContainers: [
      Color(0xFF26443D),
      Color(0xFF31404E),
      Color(0xFF5B3226),
      Color(0xFF604C25),
      Color(0xFF40243B),
    ],
    onAccentContainers: [
      Color(0xFF52BAAD), // 4.55:1
      Color(0xFF7BAEDD), // 4.53:1
      Color(0xFFF28D73), // 4.58:1
      Color(0xFFFCC64C), // 5.21:1
      Color(0xFFBF7EC4), // 4.56:1
    ],
    success: Color(0xFF7BC894),
    warning: Color(0xFFE8BC5A),
    pendingSync: Color(0xFFBFAE9E),
  );

  @override
  AppColors copyWith({
    List<Color>? accents,
    List<Color>? accentContainers,
    List<Color>? onAccentContainers,
    Color? success,
    Color? warning,
    Color? pendingSync,
  }) {
    return AppColors(
      accents: accents ?? this.accents,
      accentContainers: accentContainers ?? this.accentContainers,
      onAccentContainers: onAccentContainers ?? this.onAccentContainers,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      accents: _lerpList(accents, other.accents, t),
      accentContainers: _lerpList(accentContainers, other.accentContainers, t),
      onAccentContainers:
          _lerpList(onAccentContainers, other.onAccentContainers, t),
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      pendingSync: Color.lerp(pendingSync, other.pendingSync, t)!,
    );
  }

  static List<Color> _lerpList(List<Color> a, List<Color> b, double t) {
    return List<Color>.generate(
      a.length,
      (i) => Color.lerp(a[i], b[i], t)!,
      growable: false,
    );
  }
}

/// Açúcar sintático para `Theme.of(context).extension<AppColors>()!`.
extension AppColorsX on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:veredas/data/models/app_role.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// Perfil de um obreiro.
///
/// Note `abstract class` — sintaxe do freezed 3.x. No 2.x era `class`, e o
/// padrão antigo não compila.
@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    required String fullName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? bio,
    @Default(AppRole.obreiro) AppRole role,
    @Default(false) bool isApproved,

    /// Tipos de escala que este obreiro gerencia, vindos de `scale_managers`.
    ///
    /// Não é coluna de `profiles`: é montado pelo repositório a partir do cache
    /// local. Fica aqui porque é o que a UI precisa para decidir se mostra o FAB
    /// numa aba de escala, e carregar isso separado em cada tela seria repetição.
    @Default(<String>[]) List<String> managedScaleTypeIds,
    DateTime? updatedAt,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}

extension ProfileX on Profile {
  bool get isAdmin => role == AppRole.admin && isApproved;

  /// Pode editar as atribuições de um tipo de escala?
  ///
  /// Espelha a função `manages_scale()` do Postgres. **Isto é só UX** — a
  /// garantia real é a policy `scale_assignments_insert/update`. Se esta
  /// checagem for burlada, o servidor recusa de qualquer forma.
  bool canEditScale(String scaleTypeId) =>
      isAdmin || managedScaleTypeIds.contains(scaleTypeId);

  /// Iniciais para o avatar quando não há foto.
  ///
  /// Usa `substring` em vez de `characters` (grapheme clusters) para não puxar
  /// uma dependência só por isto. A diferença apareceria em emoji ou em texto
  /// NFD decomposto; para nomes de pessoas o pior caso é exibir "A" no lugar de
  /// "Â", o que é aceitável numa inicial.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts.last.substring(0, 1)).toUpperCase();
  }
}

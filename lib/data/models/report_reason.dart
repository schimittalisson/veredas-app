/// Motivo de uma denúncia, espelhando o CHECK de `public.content_reports`.
enum ReportReason {
  offensive('offensive'),
  spam('spam'),
  other('other');

  const ReportReason(this.wire);

  /// Valor exato gravado no banco — mesmo cuidado de `AppRole.wire`.
  final String wire;

  static ReportReason fromWire(String? value) {
    return switch (value) {
      'offensive' => ReportReason.offensive,
      'spam' => ReportReason.spam,
      _ => ReportReason.other,
    };
  }
}

/// The product's grade vocabulary.
///
/// The spec defines exactly these four values — `grade text -- A|B|C|D` in the schema, "Grade
/// selector A–D" in the UI design — and nothing else. There is deliberately no fifth value and
/// no proprietary scale: a grade the trader cannot recognise is worse than no grade.
enum TradeGrade {
  /// Fully compliant with the checklist.
  a('A'),

  /// Mostly compliant; one soft miss.
  b('B'),

  /// Compliant on outcome but weak on process (or the reverse).
  c('C'),

  /// Poor on both.
  d('D');

  const TradeGrade(this.label);

  /// The single character stored in `trades.grade`.
  final String label;

  /// Ascending quality: `D` is the worst, `A` the best.
  ///
  /// Ordering is on the enum's own index, so "is this at least a B?" is `index <= b.index`.
  int get rank => index;

  /// Human wording for the reason list. Deliberately plain — no jargon the trader must learn.
  String get description => switch (this) {
        TradeGrade.a => 'Clean execution. Process and outcome both held up.',
        TradeGrade.b => 'Good, with one small process miss.',
        TradeGrade.c => 'Outcome masked a weak process, or the reverse.',
        TradeGrade.d => 'Process broke down. Review this one.',
      };

  /// Parses the stored value.
  ///
  /// Case-insensitive and null-safe so a row written by any producer (mock, CSV import, broker
  /// sync) round-trips. Unrecognised text yields null rather than a silent default: showing
  /// "B" on a row whose grade was "Z" would be inventing data.
  static TradeGrade? tryParse(String? raw) {
    if (raw == null) return null;
    final String v = raw.trim().toUpperCase();
    if (v.isEmpty) return null;
    for (final TradeGrade g in TradeGrade.values) {
      if (g.label == v) return g;
    }
    return null;
  }

  /// The value to persist, or null when unset.
  static String? encode(TradeGrade? grade) => grade?.label;
}
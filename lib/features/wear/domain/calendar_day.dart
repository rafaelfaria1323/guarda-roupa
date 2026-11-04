/// Dia de calendário (sem hora nem fuso), no fuso de quem usa a app.
///
/// As regras de rotatividade contam dias de calendário, não blocos de 24 h
/// (docs/features/utilizacao-e-rotatividade.md, "Semântica de datas"), por
/// isso a aritmética é feita em UTC, onde não há mudanças de hora.
final class CalendarDay implements Comparable<CalendarDay> {
  CalendarDay(int year, int month, int day)
    : _utc = DateTime.utc(year, month, day) {
    if (_utc.year != year || _utc.month != month || _utc.day != day) {
      throw ArgumentError('Data impossível: $year-$month-$day');
    }
  }

  CalendarDay._(this._utc);

  /// O dia de `moment` no fuso local do dispositivo.
  factory CalendarDay.of(DateTime moment) {
    final local = moment.toLocal();
    return CalendarDay._(DateTime.utc(local.year, local.month, local.day));
  }

  /// `AAAA-MM-DD`; `null` se não for uma data válida.
  static CalendarDay? tryParse(String? text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text ?? '');
    if (m == null) return null;
    try {
      return CalendarDay(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    } on ArgumentError {
      return null;
    }
  }

  final DateTime _utc;

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  /// 1 = segunda … 7 = domingo ([DateTime.monday]…[DateTime.sunday]).
  int get weekday => _utc.weekday;

  bool get isWeekend =>
      weekday == DateTime.saturday || weekday == DateTime.sunday;

  CalendarDay addDays(int days) =>
      CalendarDay._(DateTime.utc(year, month, day + days));

  /// Dias de calendário de `this` até `other` (negativo se `other` é antes).
  int daysUntil(CalendarDay other) => other._utc.difference(_utc).inDays;

  /// Meia-noite local deste dia, para formatar.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  String get iso {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}';
  }

  bool isAfter(CalendarDay other) => compareTo(other) > 0;

  @override
  int compareTo(CalendarDay other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) => other is CalendarDay && other._utc == _utc;

  @override
  int get hashCode => _utc.hashCode;

  @override
  String toString() => iso;
}

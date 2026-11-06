/// Uma hora do dia (sem data nem fuso).
final class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  /// "21:30" ou "21:30:00" (como a base devolve um `time`).
  static ClockTime? tryParse(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (m == null) return null;
    final h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    return h < 24 && min < 60 ? ClockTime(h, min) : null;
  }

  final int hour;
  final int minute;

  /// "21:30".
  String get hhmm =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ClockTime other) =>
      (hour * 60 + minute).compareTo(other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => hhmm;
}

/// Os lembretes da conta (docs/features/lembretes.md). `null` = desligado.
/// Valem para todos os aparelhos que os recebem; o fuso é o do último
/// aparelho que mudou as horas.
final class ReminderSettings {
  const ReminderSettings({this.wearCheckAt, this.eveAt});

  static const off = ReminderSettings();

  /// "Vestiste isto?": ao fim do dia, se ainda não registaste nada.
  static const defaultWearCheckAt = ClockTime(21, 30);

  /// "Amanhã: …": na véspera, se o dia seguinte tem roupa planeada.
  static const defaultEveAt = ClockTime(20, 0);

  final ClockTime? wearCheckAt;
  final ClockTime? eveAt;

  bool get anyOn => wearCheckAt != null || eveAt != null;

  ReminderSettings copyWith({
    ClockTime? Function()? wearCheckAt,
    ClockTime? Function()? eveAt,
  }) => ReminderSettings(
    wearCheckAt: wearCheckAt == null ? this.wearCheckAt : wearCheckAt(),
    eveAt: eveAt == null ? this.eveAt : eveAt(),
  );

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.wearCheckAt == wearCheckAt &&
      other.eveAt == eveAt;

  @override
  int get hashCode => Object.hash(wearCheckAt, eveAt);
}

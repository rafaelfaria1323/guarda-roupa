import '../../wear/domain/calendar_day.dart';
import 'push_client.dart';
import 'reminder_settings.dart';

/// Os textos de um dia planeado, escritos pela app (com os nomes das peças e
/// os acessórios pelo tempo). O servidor só os usa enquanto a entrada do
/// plano estiver em [planVersion].
final class DaySummary {
  const DaySummary({
    required this.day,
    required this.planVersion,
    this.wearBody,
    this.eveBody,
  });

  final CalendarDay day;
  final int planVersion;

  /// "Vestiste …?" (no próprio dia).
  final String? wearBody;

  /// "Amanhã: …" (na véspera).
  final String? eveBody;

  Map<String, Object?> toJson() => {
    'day': day.iso,
    'plan_version': planVersion,
    'wear_body': wearBody,
    'eve_body': eveBody,
  };

  @override
  bool operator ==(Object other) =>
      other is DaySummary &&
      other.day == day &&
      other.planVersion == planVersion &&
      other.wearBody == wearBody &&
      other.eveBody == eveBody;

  @override
  int get hashCode => Object.hash(day, planVersion, wearBody, eveBody);
}

/// O servidor dos lembretes (Supabase).
abstract interface class ReminderBackend {
  /// A chave pública VAPID; `null` se o servidor ainda não a tem.
  Future<String?> publicKey();
  Future<ReminderSettings> load();
  Future<void> save(ReminderSettings settings, {required String timeZone});
  Future<void> saveDevice(PushSubscriptionKeys keys);
  Future<void> removeDevice(String endpoint);
  Future<void> saveSummaries(List<DaySummary> days);
}

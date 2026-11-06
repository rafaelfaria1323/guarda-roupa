import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/push_client.dart';
import '../domain/reminder_backend.dart';
import '../domain/reminder_settings.dart';

/// Lembretes no Supabase: definições, aparelhos e textos de cada dia
/// (migração 20261121000001_reminders.sql) e a chave pública pela função
/// `reminders`.
final class SupabaseReminderBackend implements ReminderBackend {
  SupabaseReminderBackend({
    required this.client,
    required this.supabaseUrl,
    required this.apiKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final SupabaseClient client;
  final String supabaseUrl;
  final String apiKey;
  final http.Client _http;
  String? _publicKey;

  @override
  Future<String?> publicKey() async {
    if (_publicKey != null) return _publicKey;
    final res = await _http.get(
      Uri.parse('$supabaseUrl/functions/v1/reminders'),
      headers: {'apikey': apiKey},
    );
    if (res.statusCode != 200) return null;
    final key = (jsonDecode(res.body) as Map)['publicKey'];
    return _publicKey = key is String ? key : null;
  }

  @override
  Future<ReminderSettings> load() async {
    final row = await client
        .from('reminder_settings')
        .select('wear_check_at, eve_at')
        .maybeSingle();
    if (row == null) return ReminderSettings.off;
    return ReminderSettings(
      wearCheckAt: ClockTime.tryParse(row['wear_check_at'] as String?),
      eveAt: ClockTime.tryParse(row['eve_at'] as String?),
    );
  }

  @override
  Future<void> save(ReminderSettings settings, {required String timeZone}) =>
      client.rpc<void>(
        'set_reminder_settings',
        params: {
          'p_wear_check_at': settings.wearCheckAt?.hhmm,
          'p_eve_at': settings.eveAt?.hhmm,
          'p_time_zone': timeZone,
        },
      );

  @override
  Future<void> saveDevice(PushSubscriptionKeys keys) => client.rpc<void>(
    'save_push_subscription',
    params: {
      'p_endpoint': keys.endpoint,
      'p_p256dh': keys.p256dh,
      'p_auth': keys.auth,
    },
  );

  @override
  Future<void> removeDevice(String endpoint) => client.rpc<void>(
    'remove_push_subscription',
    params: {'p_endpoint': endpoint},
  );

  @override
  Future<void> saveSummaries(List<DaySummary> days) => client.rpc<void>(
    'set_day_summaries',
    params: {
      'p_days': [for (final d in days) d.toJson()],
    },
  );
}

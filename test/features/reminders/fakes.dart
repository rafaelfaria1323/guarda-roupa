import 'dart:async';

import 'package:guarda_roupa/features/reminders/domain/push_client.dart';
import 'package:guarda_roupa/features/reminders/domain/reminder_backend.dart';
import 'package:guarda_roupa/features/reminders/domain/reminder_settings.dart';

const deviceKeys = PushSubscriptionKeys(
  endpoint: 'https://push.example/eu',
  p256dh: 'p256',
  auth: 'auth',
);

/// Um navegador com notificações; regista a ordem das chamadas.
final class FakePushClient implements PushClient {
  FakePushClient({
    this.support = PushSupport.available,
    this.permission = PushPermission.prompt,
    this.answer = PushPermission.granted,
    this.subscribed = false,
  });

  @override
  final PushSupport support;
  @override
  PushPermission permission;

  /// O que o utilizador responde ao pedido de autorização.
  final PushPermission answer;
  bool subscribed;
  final calls = <String>[];
  final opened = StreamController<String>.broadcast();

  @override
  String get timeZone => 'Europe/Lisbon';

  @override
  Future<PushPermission> requestPermission() async {
    calls.add('requestPermission');
    return permission = answer;
  }

  @override
  Future<PushSubscriptionKeys?> current() async =>
      subscribed ? deviceKeys : null;

  @override
  Future<PushSubscriptionKeys?> subscribe(String serverPublicKey) async {
    calls.add('subscribe $serverPublicKey');
    subscribed = true;
    return deviceKeys;
  }

  @override
  Future<void> unsubscribe() async {
    calls.add('unsubscribe');
    subscribed = false;
  }

  @override
  Stream<String> get openedPaths => opened.stream;
}

final class FakeReminderBackend implements ReminderBackend {
  FakeReminderBackend({this.settings = ReminderSettings.off});

  ReminderSettings settings;
  String? timeZone;
  final devices = <String>{};
  final summaries = <List<DaySummary>>[];
  final calls = <String>[];
  bool offline = false;

  void _net(String call) {
    calls.add(call);
    if (offline) throw StateError('sem rede');
  }

  @override
  Future<String?> publicKey() async {
    _net('publicKey');
    return 'BPUB';
  }

  @override
  Future<ReminderSettings> load() async {
    _net('load');
    return settings;
  }

  @override
  Future<void> save(ReminderSettings s, {required String timeZone}) async {
    _net('save');
    settings = s;
    this.timeZone = timeZone;
  }

  @override
  Future<void> saveDevice(PushSubscriptionKeys keys) async {
    _net('saveDevice');
    devices.add(keys.endpoint);
  }

  @override
  Future<void> removeDevice(String endpoint) async {
    _net('removeDevice');
    devices.remove(endpoint);
  }

  @override
  Future<void> saveSummaries(List<DaySummary> days) async {
    _net('saveSummaries');
    summaries.add(days);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/account_sync/application/providers.dart';
import 'package:guarda_roupa/features/account_sync/domain/auth_service.dart';
import 'package:guarda_roupa/features/reminders/application/reminder_providers.dart';
import 'package:guarda_roupa/features/reminders/domain/push_client.dart';
import 'package:guarda_roupa/features/reminders/domain/reminder_settings.dart';

import '../../support/fake_auth.dart';
import 'fakes.dart';

void main() {
  Future<(ProviderContainer, ReminderNotifier)> setUpWith(
    FakePushClient client,
    FakeReminderBackend backend,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(
          FakeAuthService(
            user: const AuthUser(id: 'user-a', email: 'a@example.com'),
          ),
        ),
        pushClientProvider.overrideWithValue(client),
        reminderBackendProvider.overrideWithValue(backend),
      ],
    );
    addTearDown(container.dispose);
    container.listen(reminderStateProvider, (_, _) {});
    await container.read(currentUserProvider.future);
    await container.read(reminderStateProvider.future);
    return (container, container.read(reminderStateProvider.notifier));
  }

  const both = ReminderSettings(
    wearCheckAt: ClockTime(21, 30),
    eveAt: ClockTime(20, 0),
  );

  test('ligar pede autorização antes de tudo, subscreve e guarda', () async {
    final client = FakePushClient();
    final backend = FakeReminderBackend();
    final (container, notifier) = await setUpWith(client, backend);

    expect(await notifier.apply(both), ReminderOutcome.ok);
    expect(client.calls, ['requestPermission', 'subscribe BPUB']);
    expect(backend.calls, ['load', 'publicKey', 'saveDevice', 'save']);
    expect(backend.devices, {deviceKeys.endpoint});
    expect(backend.settings, both);
    expect(backend.timeZone, 'Europe/Lisbon');
    final state = container.read(reminderStateProvider).value!;
    expect(state.thisDevice, isTrue);
    expect(state.settings, both);

    // Mudar a hora já não pede nada ao aparelho.
    client.calls.clear();
    final later = both.copyWith(eveAt: () => const ClockTime(19, 0));
    expect(await notifier.apply(later), ReminderOutcome.ok);
    expect(client.calls, isEmpty);
    expect(backend.settings.eveAt, const ClockTime(19, 0));
  });

  test('desligar os dois deixa de receber neste aparelho', () async {
    final client = FakePushClient(
      permission: PushPermission.granted,
      subscribed: true,
    );
    final backend = FakeReminderBackend(settings: both)
      ..devices.add(deviceKeys.endpoint);
    final (container, notifier) = await setUpWith(client, backend);
    expect(container.read(reminderStateProvider).value!.thisDevice, isTrue);

    expect(await notifier.apply(ReminderSettings.off), ReminderOutcome.ok);
    expect(backend.devices, isEmpty);
    expect(client.subscribed, isFalse);
    expect(backend.settings, ReminderSettings.off);
  });

  test('recusado, sem suporte ou sem rede: nada muda', () async {
    final refused = FakePushClient(answer: PushPermission.denied);
    final backend = FakeReminderBackend();
    final (_, notifier) = await setUpWith(refused, backend);
    expect(await notifier.apply(both), ReminderOutcome.denied);
    expect(backend.calls, ['load']);

    final unsupported = FakePushClient(support: PushSupport.needsInstall);
    final (_, n2) = await setUpWith(unsupported, FakeReminderBackend());
    expect(await n2.apply(both), ReminderOutcome.unsupported);
    expect(unsupported.calls, isEmpty);

    final offline = FakeReminderBackend();
    final (c3, n3) = await setUpWith(FakePushClient(), offline);
    offline.offline = true;
    expect(await n3.apply(both), ReminderOutcome.failed);
    expect(
      c3.read(reminderStateProvider).value!.settings,
      ReminderSettings.off,
    );
  });

  test('ClockTime lê o time da base', () {
    expect(ClockTime.tryParse('21:30:00'), const ClockTime(21, 30));
    expect(ClockTime.tryParse('7:05'), const ClockTime(7, 5));
    expect(ClockTime.tryParse('25:00'), isNull);
    expect(const ClockTime(9, 5).hhmm, '09:05');
  });
}

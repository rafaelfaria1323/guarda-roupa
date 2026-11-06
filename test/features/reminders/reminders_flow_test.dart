import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/reminders/application/reminder_providers.dart';
import 'package:guarda_roupa/features/reminders/domain/reminder_settings.dart';
import 'package:guarda_roupa/features/reminders/presentation/reminder_sync.dart';
import 'package:guarda_roupa/features/wear/application/wear_providers.dart';

import '../../support/app_harness.dart';
import '../wardrobe/domain/fakes.dart';
import 'fakes.dart';

void main() {
  testWidgets('ligar os lembretes, enviar os textos da semana e abrir o '
      '"Vesti hoje" pela notificação', (tester) async {
    final client = FakePushClient();
    final backend = FakeReminderBackend();
    final app = await pumpApp(
      tester,
      overrides: [
        clockProvider.overrideWithValue(
          FixedClock(DateTime.utc(2026, 11, 6, 12)),
        ),
        pushClientProvider.overrideWithValue(client),
        reminderBackendProvider.overrideWithValue(backend),
      ],
    );
    await tester.runAsync(() async {
      for (final (id, category, name) in [
        ('g1', 't_shirt', 'T-shirt branca'),
        ('g2', 'jeans', 'Calças azuis'),
        ('g3', 'umbrella', null),
      ]) {
        await app.db.execute(
          'INSERT INTO garments (id, owner_id, category, name, availability, '
          'created_at, updated_at, version) VALUES '
          "(?, 'user-a', ?, ?, 'available', '2026-11-01T10:00:00Z', "
          "'2026-11-01T10:00:00Z', 1)",
          [id, category, name],
        );
      }
      for (final (id, day, version) in [
        ('e1', '2026-11-06', 1),
        ('e2', '2026-11-07', 3),
      ]) {
        await app.db.execute(
          'INSERT INTO plan_entries (id, owner_id, day, occasion, tentative, '
          'items, status, version, created_at, updated_at) VALUES '
          "(?, 'user-a', ?, 'casual', 0, ?, 'accepted', ?, "
          "'2026-11-05T10:00:00Z', '2026-11-05T10:00:00Z')",
          [
            id,
            day,
            '[{"garment_id":"g1","role":"main_top"},'
                '{"garment_id":"g2","role":"bottom"}]',
            version,
          ],
        );
      }
    });
    await settle(tester);

    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('reminder-settings')));
    await settle(tester);
    expect(find.text('Desligados'), findsNothing);
    await tester.tap(find.byKey(const Key('reminders-wear')));
    await settleUntil(tester, find.byKey(const Key('reminders-wear-time')));

    expect(client.calls, ['requestPermission', 'subscribe BPUB']);
    expect(
      backend.settings,
      const ReminderSettings(wearCheckAt: ClockTime(21, 30)),
    );
    expect(find.text('Às 21:30'), findsOne);
    expect(find.byKey(const Key('reminders-this-device')), findsOne);

    await tester.tap(find.byKey(const Key('reminders-eve')));
    await settleUntil(tester, find.byKey(const Key('reminders-eve-time')));
    expect(backend.settings.eveAt, ReminderSettings.defaultEveAt);
    expect(client.calls, hasLength(2), reason: 'já subscrito');

    // Os textos seguem depois de uma pequena espera.
    await tester.pump(ReminderSync.debounce + const Duration(seconds: 1));
    await settle(tester);
    final days = backend.summaries.last;
    expect([for (final d in days) d.day.iso], ['2026-11-06', '2026-11-07']);
    expect(days[0].planVersion, 1);
    expect(
      days[0].wearBody,
      'Vestiste T-shirt branca e Calças azuis? Toca para confirmar.',
    );
    expect(days[1].planVersion, 3);
    expect(days[1].eveBody, 'Amanhã: T-shirt branca e Calças azuis.');

    // Nada mudou: não envia de novo.
    final sent = backend.summaries.length;
    await tester.pump(ReminderSync.debounce * 2);
    await settle(tester);
    expect(backend.summaries, hasLength(sent));

    // Tocar na notificação com a app aberta.
    client.opened.add('/vesti?pecas=g1,g2&plano=e1');
    await settleUntil(tester, find.byKey(const Key('wear-save')));
    expect(find.byKey(const Key('wear-selected')), findsOne);

    // Desligar os dois deixa de receber neste aparelho.
    Navigator.of(tester.element(find.byKey(const Key('wear-save')))).pop();
    await settle(tester);
    await tester.tap(find.byKey(const Key('reminders-wear')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('reminders-eve')));
    await settleUntil(
      tester,
      find.byKey(const Key('reminders-this-device')),
      gone: true,
    );
    expect(backend.devices, isEmpty);
    expect(client.subscribed, isFalse);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../data/push_client_factory.dart';
import '../domain/push_client.dart';
import '../domain/reminder_backend.dart';
import '../domain/reminder_settings.dart';

/// As notificações do navegador; fora da Web não há.
final pushClientProvider = Provider<PushClient>((_) => createPushClient());

/// `null` sem Supabase (a app funciona, mas sem lembretes).
final reminderBackendProvider = Provider<ReminderBackend?>((_) => null);

/// Os lembretes da conta e se este aparelho os recebe.
final class ReminderState {
  const ReminderState({required this.settings, required this.thisDevice});

  final ReminderSettings settings;

  /// Este aparelho está subscrito (recebe as notificações).
  final bool thisDevice;
}

/// O que aconteceu ao mudar os lembretes.
enum ReminderOutcome {
  ok,

  /// O utilizador (ou o aparelho) não deixou mostrar notificações.
  denied,

  /// Este aparelho não recebe notificações (ou falta instalar a app).
  unsupported,

  /// Sem rede, ou o servidor ainda não está pronto.
  failed,
}

final reminderStateProvider =
    AsyncNotifierProvider<ReminderNotifier, ReminderState?>(
      ReminderNotifier.new,
    );

class ReminderNotifier extends AsyncNotifier<ReminderState?> {
  @override
  Future<ReminderState?> build() async {
    final user = ref.watch(currentUserProvider).value;
    final backend = ref.watch(reminderBackendProvider);
    if (user == null || backend == null) return null;
    final client = ref.watch(pushClientProvider);
    final settings = await backend.load();
    final device = client.support == PushSupport.available
        ? await client.current()
        : null;
    return ReminderState(settings: settings, thisDevice: device != null);
  }

  /// Guarda as horas. Ligar um lembrete num aparelho que ainda não os recebe
  /// pede autorização e subscreve-o; desligar os dois deixa de os receber
  /// aqui. Chamar logo no toque: o pedido de autorização vem primeiro.
  Future<ReminderOutcome> apply(ReminderSettings next) async {
    final backend = ref.read(reminderBackendProvider);
    final client = ref.read(pushClientProvider);
    final current = state.value;
    if (backend == null || current == null) return ReminderOutcome.failed;
    if (next.anyOn && !current.thisDevice) {
      if (client.support != PushSupport.available) {
        return ReminderOutcome.unsupported;
      }
      // Antes de qualquer espera pela rede (no iPhone tem de ser no toque).
      final permission = client.permission == PushPermission.granted
          ? PushPermission.granted
          : await client.requestPermission();
      if (permission != PushPermission.granted) return ReminderOutcome.denied;
    }
    try {
      var thisDevice = current.thisDevice;
      if (next.anyOn && !thisDevice) {
        final key = await backend.publicKey();
        if (key == null) return ReminderOutcome.failed;
        final keys = await client.subscribe(key);
        if (keys == null) return ReminderOutcome.denied;
        await backend.saveDevice(keys);
        thisDevice = true;
      }
      await backend.save(next, timeZone: client.timeZone);
      if (!next.anyOn && thisDevice) {
        final keys = await client.current();
        if (keys != null) await backend.removeDevice(keys.endpoint);
        await client.unsubscribe();
        thisDevice = false;
      }
      state = AsyncData(ReminderState(settings: next, thisDevice: thisDevice));
      return ReminderOutcome.ok;
    } on Object {
      return ReminderOutcome.failed;
    }
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../care/application/care_providers.dart';
import '../../planner/application/plan_providers.dart';
import '../../wear/application/wear_providers.dart';
import '../application/reminder_providers.dart';
import '../domain/reminder_backend.dart';
import 'reminder_texts.dart';

/// Com os lembretes ligados, manda ao servidor os textos dos dias planeados
/// sempre que a semana muda (com uma pequena espera, para juntar mudanças);
/// e abre o ecrã certo quando se toca numa notificação com a app aberta.
class ReminderSync extends ConsumerStatefulWidget {
  const ReminderSync({required this.child, super.key});

  final Widget child;

  /// Espera antes de enviar, para juntar várias mudanças seguidas.
  static const debounce = Duration(seconds: 2);

  @override
  ConsumerState<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends ConsumerState<ReminderSync> {
  Timer? _timer;
  List<DaySummary>? _sent;
  StreamSubscription<String>? _opened;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      _inputsProvider,
      (_, _) => _schedule(),
      fireImmediately: true,
    );
    _opened = ref.read(pushClientProvider).openedPaths.listen((path) {
      final router = ref.read(routerProvider);
      // "Vesti hoje" abre por cima; o resto é um separador.
      if (path.startsWith(AppRoutes.wear)) {
        unawaited(router.push(path));
      } else {
        router.go(path);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_opened?.cancel());
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(ReminderSync.debounce, () {
      if (mounted) unawaited(_send());
    });
  }

  Future<void> _send() async {
    final inputs = ref.read(_inputsProvider);
    final backend = ref.read(reminderBackendProvider);
    if (inputs == null || backend == null) return;
    final days = daySummaries(
      l10n: AppLocalizations.of(context),
      today: inputs.today,
      week: inputs.week,
      accessories: ref.read(weekAccessoriesProvider),
      garments: {for (final g in inputs.garments) g.id: g},
    );
    if (_sameAs(_sent, days)) return;
    try {
      await backend.saveSummaries(days);
      _sent = days;
    } on Object {
      // Sem rede: tenta-se de novo na próxima mudança.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  static bool _sameAs(List<DaySummary>? a, List<DaySummary> b) =>
      a != null &&
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
}

/// O que entra nos textos; `null` com os lembretes desligados ou a carregar.
final _inputsProvider = Provider.autoDispose((ref) {
  final on = ref.watch(
    reminderStateProvider.select((s) => s.value?.settings.anyOn ?? false),
  );
  if (!on) return null;
  final week = ref.watch(weekViewProvider);
  final garments = ref.watch(allGarmentsProvider).value;
  // Os acessórios também mudam os textos.
  ref.watch(weekAccessoriesProvider);
  if (week == null || garments == null) return null;
  return (
    today: todayFrom(ref.watch(clockProvider)),
    week: week,
    garments: garments,
  );
});

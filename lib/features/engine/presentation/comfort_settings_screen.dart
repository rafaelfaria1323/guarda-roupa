import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/suggestion_providers.dart';
import '../domain/comfort.dart';

/// Editar os limites de conforto (P-17). Valem para as sugestões de hoje,
/// para o planeamento da semana e para a revisão do plano.
class ComfortSettingsScreen extends ConsumerStatefulWidget {
  const ComfortSettingsScreen({super.key});

  @override
  ConsumerState<ComfortSettingsScreen> createState() =>
      _ComfortSettingsScreenState();
}

class _ComfortSettingsScreenState extends ConsumerState<ComfortSettingsScreen> {
  ComfortThresholds? _draft;

  Future<void> _save(ComfortThresholds value) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(comfortThresholdsProvider.notifier).save(value);
    if (!mounted) return;
    setState(() => _draft = null);
    messenger.showSnackBar(SnackBar(content: Text(l10n.comfortSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(comfortThresholdsProvider).value;
    if (saved == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.comfortTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final t = _draft ?? saved;
    // Parte do estado atual, não do `t` desta construção: dois toques
    // seguidos antes de redesenhar somam-se.
    void edit(ComfortThresholds Function(ComfortThresholds) change) {
      final next = change(_draft ?? saved);
      if (next.isValid) setState(() => _draft = next);
    }

    ComfortThresholds hot(ComfortThresholds b, double d) => ComfortThresholds(
      hotFromC: b.hotFromC + d,
      coldBelowC: b.coldBelowC,
      windyFromKmh: b.windyFromKmh,
    );
    ComfortThresholds cold(ComfortThresholds b, double d) => ComfortThresholds(
      hotFromC: b.hotFromC,
      coldBelowC: b.coldBelowC + d,
      windyFromKmh: b.windyFromKmh,
    );
    ComfortThresholds wind(ComfortThresholds b, double d) => ComfortThresholds(
      hotFromC: b.hotFromC,
      coldBelowC: b.coldBelowC,
      windyFromKmh: b.windyFromKmh + d,
    );
    const defaults = ComfortThresholds();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.comfortTitle),
        actions: [
          TextButton(
            key: const Key('comfort-save'),
            onPressed: _draft == null || _draft == saved
                ? null
                : () => _save(_draft!),
            child: Text(l10n.garmentSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.comfortIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          _Stepper(
            id: 'hot',
            label: l10n.comfortHot,
            value: l10n.comfortDegrees(t.hotFromC.round()),
            help: l10n.comfortHotHelp,
            onMinus: () => edit((b) => hot(b, -1)),
            onPlus: () => edit((b) => hot(b, 1)),
            canMinus: hot(t, -1).isValid,
            canPlus: hot(t, 1).isValid,
          ),
          _Stepper(
            id: 'cold',
            label: l10n.comfortCold,
            value: l10n.comfortDegrees(t.coldBelowC.round()),
            help: l10n.comfortColdHelp,
            onMinus: () => edit((b) => cold(b, -1)),
            onPlus: () => edit((b) => cold(b, 1)),
            canMinus: cold(t, -1).isValid,
            canPlus: cold(t, 1).isValid,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              l10n.comfortMild(t.coldBelowC.round(), t.hotFromC.round()),
              key: const Key('comfort-mild'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          _Stepper(
            id: 'wind',
            label: l10n.comfortWind,
            value: l10n.comfortKmh(t.windyFromKmh.round()),
            help: l10n.comfortWindHelp,
            onMinus: () => edit((b) => wind(b, -5)),
            onPlus: () => edit((b) => wind(b, 5)),
            canMinus: wind(t, -5).isValid,
            canPlus: wind(t, 5).isValid,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('comfort-reset'),
              onPressed: t == defaults ? null : () => edit((_) => defaults),
              child: Text(l10n.comfortReset),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.id,
    required this.label,
    required this.value,
    required this.help,
    required this.onMinus,
    required this.onPlus,
    required this.canMinus,
    required this.canPlus,
  });

  final String id;
  final String label;
  final String value;
  final String help;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool canMinus;
  final bool canPlus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
              IconButton(
                key: Key('comfort-$id-minus'),
                tooltip: l10n.comfortLess(label),
                onPressed: canMinus ? onMinus : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  value,
                  key: Key('comfort-$id-value'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: Key('comfort-$id-plus'),
                tooltip: l10n.comfortMore(label),
                onPressed: canPlus ? onPlus : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text(help, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

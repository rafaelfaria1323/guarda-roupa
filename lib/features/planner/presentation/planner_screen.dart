import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../engine/presentation/today_suggestions_card.dart';
import '../../wear/application/wear_providers.dart';
import '../../wear/presentation/today_wear_card.dart';
import 'week_plan_card.dart';

/// "Hoje" (visual fio v2): uma saudação, o tempo, a sugestão do dia como
/// um flat-lay, o que já vestiste e a semana como um fio com nós.
class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
    children: const [
      _Greeting(),
      SizedBox(height: 6),
      TodaySuggestionsCard(),
      SizedBox(height: 28),
      TodayWearCard(),
      SizedBox(height: 28),
      WeekPlanCard(),
    ],
  );
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = ref.watch(clockProvider).nowUtc().toLocal().hour;
    final part = switch (hour) {
      >= 5 && < 12 => 'morning',
      >= 12 && < 20 => 'afternoon',
      _ => 'night',
    };
    return Text(
      AppLocalizations.of(context).todayGreeting(part),
      key: const Key('today-greeting'),
      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 40),
    );
  }
}

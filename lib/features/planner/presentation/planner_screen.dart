import 'package:flutter/material.dart';

import '../../engine/presentation/today_suggestions_card.dart';
import '../../wear/presentation/today_wear_card.dart';
import 'week_plan_card.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const [
      TodayWearCard(),
      SizedBox(height: 8),
      TodaySuggestionsCard(),
      SizedBox(height: 8),
      WeekPlanCard(),
    ],
  );
}

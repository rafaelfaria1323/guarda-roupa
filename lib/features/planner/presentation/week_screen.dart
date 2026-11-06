import 'package:flutter/material.dart';

import 'week_plan_card.dart';

/// Separador Semana (design v3): o plano dos próximos dias, que se enche
/// sozinho e se ajusta ao tempo.
class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
    children: const [WeekPlanCard()],
  );
}

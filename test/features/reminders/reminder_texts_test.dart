import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/engine/domain/suggestion.dart';
import 'package:guarda_roupa/features/outfits/domain/outfit.dart';
import 'package:guarda_roupa/features/planner/application/plan_providers.dart';
import 'package:guarda_roupa/features/planner/domain/plan_entry.dart';
import 'package:guarda_roupa/features/reminders/presentation/reminder_texts.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/l10n/app_localizations.dart';

import '../engine/daily_engine_test.dart' show g;

void main() {
  final l10n = lookupAppLocalizations(const Locale('pt'));
  final today = CalendarDay(2026, 11, 6);
  final shirt = g('t', GarmentCategory.tShirt);
  final jeans = g('j', GarmentCategory.jeans);
  final shoes = g('s', GarmentCategory.sneakers);
  final umbrella = g('u', GarmentCategory.umbrella);
  final garments = {
    for (final x in [shirt, jeans, shoes, umbrella]) x.id: x,
  };

  WeekDayView day(int offset, {PlanDayState state = PlanDayState.accepted}) {
    final d = today.addDays(offset);
    return WeekDayView(
      day: d,
      state: state,
      entry: PlanEntry(
        id: 'e$offset',
        day: d,
        items: [
          OutfitItem(shirt.id, OutfitRole.mainTop),
          OutfitItem(jeans.id, OutfitRole.bottom),
          OutfitItem(shoes.id, OutfitRole.footwear),
        ],
        status: PlanStatus.accepted,
        version: 2,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  }

  test('nomes das peças e, só para hoje e amanhã, os acessórios', () {
    final rain = [SuggestedItem(umbrella, OutfitRole.accessory, const [])];
    final days = daySummaries(
      l10n: l10n,
      today: today,
      week: [
        day(0, state: PlanDayState.confirmed),
        day(1),
        day(3),
        WeekDayView(day: today.addDays(4), state: null),
      ],
      accessories: {today.addDays(1): rain, today.addDays(3): rain},
      garments: garments,
    );
    expect([for (final d in days) d.day], [today.addDays(1), today.addDays(3)]);
    expect(days[0].planVersion, 2);
    expect(
      days[0].wearBody,
      'Vestiste T-shirt, Calças de ganga e Ténis? Toca para confirmar.',
    );
    expect(
      days[0].eveBody,
      'Amanhã: T-shirt, Calças de ganga e Ténis. Leva também: Chapéu-de-chuva.',
    );
    expect(days[1].eveBody, 'Amanhã: T-shirt, Calças de ganga e Ténis.');
  });
}

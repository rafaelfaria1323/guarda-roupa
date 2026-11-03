import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/weather/application/weather_providers.dart';
import 'package:guarda_roupa/features/weather/data/weather_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/app_harness.dart';

void main() {
  Future<void> openLocation(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    expect(find.text('Torres Vedras'), findsOneWidget);
    await tester.tap(find.byKey(const Key('weather-location')));
    await settle(tester);
  }

  testWidgets('pesquisa e escolhe outra localidade', (tester) async {
    final (:auth, :db) = await pumpApp(
      tester,
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient(
            (req) async => http.Response(
              jsonEncode({
                'results': [
                  {
                    'name': 'Porto',
                    'admin1': 'Porto',
                    'latitude': 41.14961,
                    'longitude': -8.61099,
                    'timezone': 'Europe/Lisbon',
                  },
                ],
              }),
              200,
            ),
          ),
        ),
      ],
    );
    await openLocation(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('weather-location-current')),
        matching: find.text('Torres Vedras'),
      ),
      findsOneWidget,
    );
    expect(find.text('Dados meteorológicos: Open-Meteo.com'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('weather-location-search')),
      'Porto',
    );
    await tester.tap(find.byKey(const Key('weather-location-search-go')));
    await settle(tester);
    expect(find.text('Porto · 41.15, -8.61'), findsOneWidget);

    await tester.tap(find.byKey(const Key('weather-location-result-0')));
    await settle(tester);
    expect(find.text('Localização: Porto'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('weather-location-current')),
        matching: find.text('Porto'),
      ),
      findsWidgets, // nome e região
    );

    final stored = await tester.runAsync(() => WeatherLocationStore(db).get());
    expect(stored!.name, 'Porto');
    expect(stored.latitude, 41.15);
  });

  testWidgets('sem rede diz que não conseguiu pesquisar', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((_) async => throw http.ClientException('offline')),
        ),
      ],
    );
    await openLocation(tester);
    await tester.enterText(
      find.byKey(const Key('weather-location-search')),
      'Porto',
    );
    await tester.tap(find.byKey(const Key('weather-location-search-go')));
    await settle(tester);
    expect(find.byKey(const Key('weather-location-failed')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('weather-location-current')),
        matching: find.text('Torres Vedras'),
      ),
      findsOneWidget,
    );
  });
}

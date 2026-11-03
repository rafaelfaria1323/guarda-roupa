import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/app/app.dart';

Future<void> pumpApp(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: GuardaRoupaApp()));
  await tester.pumpAndSettle();
}

void main() {
  const phone = Size(400, 800);
  const desktop = Size(1200, 800);

  testWidgets('abre no Planeador com navegação inferior num telemóvel', (
    tester,
  ) async {
    await pumpApp(tester, size: phone);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Ainda não há planeamento.'), findsOneWidget);
  });

  testWidgets('muda de separador e mantém o título coerente', (tester) async {
    await pumpApp(tester, size: phone);

    await tester.tap(find.byIcon(Icons.checkroom_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não tens peças.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Guarda-roupa'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.style_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não há conjuntos guardados.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não há inspirações.'), findsOneWidget);
  });

  testWidgets('usa navegação lateral em ecrãs largos', (tester) async {
    await pumpApp(tester, size: desktop);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('abre e fecha as Definições', (tester) async {
    await pumpApp(tester, size: phone);

    await tester.tap(find.byTooltip('Definições'));
    await tester.pumpAndSettle();
    expect(find.text('Conta e sincronização'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não há planeamento.'), findsOneWidget);
  });
}

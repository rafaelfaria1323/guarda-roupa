import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/backup/application/backup_providers.dart';
import 'package:guarda_roupa/features/backup/data/backup_codec.dart';
import 'package:guarda_roupa/features/backup/domain/backup.dart';
import 'package:guarda_roupa/features/backup/domain/backup_picker.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wear/domain/calendar_day.dart';
import 'package:guarda_roupa/features/wear/domain/wear_event.dart';

import '../../support/app_harness.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show addGarment, inList, openWardrobe;

final class FakePicker implements BackupPicker {
  FakePicker(this.file);
  Uint8List? file;

  @override
  Future<Uint8List?> pick() async => file;
}

Uint8List backupWith(List<String> names) => BackupCodec.encode(
  garments: [
    for (final (i, name) in names.indexed)
      Garment(
        id: GarmentId('00000000-0000-4000-8000-00000000000$i'),
        category: GarmentCategory.shirt,
        name: name,
        availability: Availability.available,
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 2),
      ),
  ],
  photoFiles: const {},
  exportedAt: DateTime.utc(2026, 11, 1, 12),
  pendingOperations: 2,
  history: BackupHistory(
    wears: [
      if (names.isNotEmpty)
        WearEvent(
          id: 'w1',
          wornOn: CalendarDay(2026, 10, 30),
          garmentIds: [GarmentId('00000000-0000-4000-8000-000000000000')],
          createdAt: DateTime.utc(2026, 10, 30, 9),
        ),
    ],
  ),
);

void main() {
  Future<void> openSettings(WidgetTester tester, FakePicker picker) async {
    await pumpApp(
      tester,
      overrides: [backupPickerProvider.overrideWithValue(picker)],
    );
  }

  Future<void> tapRestore(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    // A lista das Definições é preguiçosa: o botão pode ainda não existir.
    await tester.scrollUntilVisible(
      find.byKey(const Key('backup-restore')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('backup-restore')));
    await settleUntil(tester, find.byType(AlertDialog));
  }

  testWidgets('mostra o conteúdo, recupera ao confirmar e aparece na lista', (
    tester,
  ) async {
    await openSettings(tester, FakePicker(backupWith(['Azul', 'Branca'])));
    await tapRestore(tester);

    expect(find.text('Recuperar este backup?'), findsOneWidget);
    expect(find.text('Feito a 1 de novembro de 2026.'), findsOneWidget);
    expect(find.text('2 peças e nenhuma fotografia.'), findsOneWidget);
    expect(find.textContaining('Inclui 2 alterações'), findsOneWidget);
    expect(
      find.text('1 utilização e nenhuma limpeza registadas.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('backup-restore-confirm')));
    await settleUntil(tester, find.text('Recuperadas 2 peças.'));

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await openWardrobe(tester);
    expect(inList('Azul'), findsOneWidget);
    expect(inList('Branca'), findsOneWidget);
  });

  testWidgets('cancelar no preview não altera nada', (tester) async {
    await openSettings(tester, FakePicker(backupWith(['Azul'])));
    await tapRestore(tester);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await openWardrobe(tester);
    expect(inList('Azul'), findsNothing);
  });

  testWidgets('conta com peças: explica e não recupera', (tester) async {
    await openSettings(tester, FakePicker(backupWith(['Azul'])));
    await openWardrobe(tester);
    await addGarment(tester, category: 'Saia', name: 'Já cá');
    await tapRestore(tester);
    expect(find.textContaining('Esta conta já tem peças.'), findsOneWidget);
    expect(find.text('Recuperar este backup?'), findsNothing);
  });

  testWidgets('ficheiro que não é backup: explica', (tester) async {
    await openSettings(tester, FakePicker(Uint8List.fromList([1, 2])));
    await tapRestore(tester);
    expect(
      find.text('Este ficheiro não é um backup do Guarda-roupa.'),
      findsOneWidget,
    );
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/backup/application/backup_providers.dart';
import 'package:guarda_roupa/features/backup/data/backup_codec.dart';
import 'package:guarda_roupa/features/backup/domain/backup_saver.dart';

import '../../support/app_harness.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart'
    show addGarment, openWardrobe;

final class FakeSaver implements BackupSaver {
  SaveOutcome outcome = SaveOutcome.saved;
  final saved = <String, Uint8List>{};

  @override
  Future<SaveOutcome> save(String name, Uint8List zip) async {
    if (outcome != SaveOutcome.cancelled) saved[name] = zip;
    return outcome;
  }
}

void main() {
  Future<FakeSaver> openSettings(WidgetTester tester) async {
    final saver = FakeSaver();
    await pumpApp(
      tester,
      overrides: [backupSaverProvider.overrideWithValue(saver)],
    );
    await openWardrobe(tester);
    await addGarment(tester, category: 'Camisa', name: 'Azul');
    await tester.tap(find.byTooltip('Definições'));
    await settle(tester);
    // A lista é preguiçosa: o backup fica no fim.
    await tester.scrollUntilVisible(
      find.byKey(const Key('backup-export')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    return saver;
  }

  Future<void> export(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('backup-export')));
    await settleUntil(tester, find.byType(SnackBar));
  }

  testWidgets('exporta um backup válido e confirma que ficou guardado', (
    tester,
  ) async {
    final saver = await openSettings(tester);
    await export(tester);

    expect(find.text('Backup guardado.'), findsOneWidget);
    final MapEntry(key: name, value: zip) = saver.saved.entries.single;
    expect(name, startsWith('guarda-roupa-'));
    final contents = switch (BackupCodec.decode(zip)) {
      Ok(:final value) => value,
      Err(:final failure) => fail('$failure'),
    };
    expect(contents.garments.single.name, 'Azul');
    expect(contents.summary.pendingOperations, 1);
  });

  testWidgets('na Web avisa que a transferência não prova a gravação', (
    tester,
  ) async {
    final saver = await openSettings(tester);
    saver.outcome = SaveOutcome.downloadStarted;
    await export(tester);
    expect(find.textContaining('Transferência iniciada'), findsOneWidget);
  });

  testWidgets('cancelar o diálogo não mostra sucesso', (tester) async {
    final saver = await openSettings(tester);
    saver.outcome = SaveOutcome.cancelled;
    await tester.tap(find.byKey(const Key('backup-export')));
    await settle(tester);
    expect(find.byType(SnackBar), findsNothing);
    expect(saver.saved, isEmpty);
  });
}

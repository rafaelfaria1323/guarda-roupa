import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/import/application/import_providers.dart';
import 'package:guarda_roupa/features/import/domain/product_import.dart';
import 'package:guarda_roupa/features/import/presentation/import_link_screen.dart';

import '../../support/app_harness.dart';
import '../../support/fake_photos.dart';
import '../../support/test_database.dart';
import '../wardrobe/presentation/wardrobe_flow_test.dart' show openWardrobe;

const url = 'https://www.zara.com/pt/pt/camisa-p1.html';

final sample = ProductPreview(
  storeName: 'Zara',
  url: url,
  name: 'Camisa de linho',
  brand: 'Zara',
  description: 'Camisa de manga comprida.',
  material: '100% linho',
  images: const [
    'https://static.zara.net/a.jpg',
    'https://static.zara.net/b.jpg',
  ],
  variants: const [
    ImportVariant(color: 'Branco', size: 'M'),
    ImportVariant(
      color: 'Azul',
      size: 'M',
      image: 'https://static.zara.net/b.jpg',
    ),
  ],
  sources: const {'name': ImportSource.jsonLd},
  confirm: const {'category', 'colors', 'owned', 'variant'},
);

final class FakeImporter implements ProductImporter {
  Result<ProductPreview, ImportFailure> next = Ok(sample);
  final previews = <String>[];
  final images = <String>[];

  @override
  Future<Result<ProductPreview, ImportFailure>> preview(String url) async {
    previews.add(url);
    return next;
  }

  @override
  Future<Result<Uint8List, ImportFailure>> image(String url) async {
    images.add(url);
    return Ok(testPng());
  }
}

Future<Map<String, Object?>> created(
  WidgetTester tester,
  PowerSyncDatabase db,
) async {
  final ops = (await tester.runAsync(() => pendingOperations(db)))!;
  final create = ops.firstWhere((o) => o['kind'] == 'create');
  return (jsonDecode(create['data']! as String) as Map).cast<String, Object?>();
}

Future<void> openImport(WidgetTester tester, String link) async {
  await tester.tap(find.text('Adicionar peça'));
  await settle(tester);
  await tester.tap(find.byKey(const Key('garment-import')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('import-url')), link);
  await tester.tap(find.byKey(const Key('import-read')));
  await tester.pumpAndSettle();
}

Future<void> chooseCategoryAndSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('garment-category')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Camisa').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('garment-save')));
  await settleUntil(tester, find.byKey(const Key('garment-save')), gone: true);
}

void main() {
  testWidgets('link da loja: escolhe a variante e a imagem, confirma, guarda', (
    tester,
  ) async {
    final importer = FakeImporter();
    final app = await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await openImport(tester, url);

    expect(importer.previews, [url]);
    expect(find.text('Zara · site novo'), findsOneWidget);
    expect(find.text('Camisa de linho'), findsOneWidget);
    expect(find.text('Nome · dados da página'), findsOneWidget);
    expect(find.text('Qual é a tua?'), findsOneWidget);

    // A variante azul traz a sua imagem.
    await tester.tap(find.byKey(const Key('import-variant-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('import-use')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ImportLinkScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('import-use')));
    await settleUntil(tester, find.byKey(const Key('garment-save')));
    await settle(tester);

    expect(importer.images, ['https://static.zara.net/b.jpg']);
    expect(
      find.text('Dados importados. Confirma a categoria e as cores.'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget, reason: 'foto por guardar');

    // Nada gravado antes de Guardar.
    expect((await tester.runAsync(() => pendingOperations(app.db)))!, isEmpty);
    await chooseCategoryAndSave(tester);

    final payload = await created(tester, app.db);
    expect(payload['name'], 'Camisa de linho');
    expect(payload['brand'], 'Zara');
    expect(
      payload['notes'],
      'Camisa de manga comprida.\n\nCor na loja: Azul\nTamanho: M\n$url',
    );
    final ops = (await tester.runAsync(() => pendingOperations(app.db)))!;
    expect(ops.map((o) => o['kind']), ['create', 'attach_photo']);
  });

  testWidgets('página sem dados: diz porquê e deixa preencher à mão', (
    tester,
  ) async {
    final importer = FakeImporter()..next = const Err(NoMetadata());
    final app = await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await openImport(tester, 'https://loja.example/p/1');

    expect(find.text('A página não tem os dados do produto.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-manual')));
    await tester.pumpAndSettle();
    await chooseCategoryAndSave(tester);

    final payload = await created(tester, app.db);
    expect(payload['notes'], 'https://loja.example/p/1');
    expect(payload['name'], isNull);
  });

  testWidgets('página bloqueada e quota esgotada têm mensagens próprias', (
    tester,
  ) async {
    final importer = FakeImporter()..next = const Err(FetchFailed('blocked'));
    await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await openImport(tester, url);
    expect(find.text('A loja não deixou ler a página.'), findsOneWidget);

    importer.next = const Err(RateLimited());
    await tester.tap(find.byKey(const Key('import-read')));
    await tester.pumpAndSettle();
    expect(
      find.text('Muitas importações seguidas. Tenta mais tarde.'),
      findsOneWidget,
    );
  });

  testWidgets('sem Supabase configurado, o botão não aparece', (tester) async {
    await pumpApp(tester);
    await openWardrobe(tester);
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    expect(find.byKey(const Key('garment-import')), findsNothing);
  });
}

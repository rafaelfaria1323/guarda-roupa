import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final shared = <SharedPage>[];
  final images = <String>[];

  @override
  Future<Result<ProductPreview, ImportFailure>> preview(String url) async {
    previews.add(url);
    return next;
  }

  @override
  Future<Result<ProductPreview, ImportFailure>> previewShared(
    SharedPage page,
  ) async {
    shared.add(page);
    return next;
  }

  @override
  Future<Result<Uint8List, ImportFailure>> image(String url) async {
    images.add(url);
    return Ok(testPng());
  }

  final inboxItems = <InboxItem>[];
  final discarded = <String>[];
  ShortcutKeyStatus keyStatus = const ShortcutKeyStatus(active: false);
  var keysCreated = 0;

  @override
  Future<Result<List<InboxItem>, ImportFailure>> inbox() async =>
      Ok([...inboxItems]);

  final inspirationItems = <InspirationInboxItem>[];

  @override
  Future<Result<List<InspirationInboxItem>, ImportFailure>>
  inspirationInbox() async => Ok([...inspirationItems]);

  @override
  Future<Result<void, ImportFailure>> discardInbox(String id) async {
    discarded.add(id);
    inboxItems.removeWhere((i) => i.id == id);
    inspirationItems.removeWhere((i) => i.id == id);
    return const Ok(null);
  }

  @override
  Future<Result<ShortcutKeyStatus, ImportFailure>> shortcutKeyStatus() async =>
      Ok(keyStatus);

  @override
  Future<Result<String, ImportFailure>> createShortcutKey() async {
    keysCreated++;
    keyStatus = ShortcutKeyStatus(active: true, createdAt: DateTime(2026));
    return Ok('fio_chave$keysCreated');
  }

  @override
  Future<Result<void, ImportFailure>> revokeShortcutKey() async {
    keyStatus = const ShortcutKeyStatus(active: false);
    return const Ok(null);
  }

  @override
  String get shortcutEndpoint =>
      'https://x.supabase.co/functions/v1/import-product?apikey=pub';
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
    expect(
      find.text(
        'Esta loja bloqueia leituras automáticas. Preenche à mão: o link fica nas notas.',
      ),
      findsOneWidget,
    );

    importer.next = const Err(RateLimited());
    await tester.tap(find.byKey(const Key('import-read')));
    await tester.pumpAndSettle();
    expect(
      find.text('Muitas importações seguidas. Tenta mais tarde.'),
      findsOneWidget,
    );
  });

  testWidgets('loja bloqueada: dica do atalho e "Colar do atalho"', (
    tester,
  ) async {
    final importer = FakeImporter()..next = const Err(FetchFailed('blocked'));
    await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await openImport(tester, url);
    expect(find.byKey(const Key('import-blocked-shortcut')), findsOneWidget);

    // O que está copiado não é do atalho.
    var clipboard = 'olá';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': clipboard}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const Key('import-paste-shared')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-not-shared')), findsOneWidget);
    expect(importer.shared, isEmpty);

    // O texto do atalho: pré-visualização sem pedir a página à loja.
    clipboard = jsonEncode({
      'fio': 1,
      'url': url,
      'title': 'CAMISA',
      'ld': ['{}'],
      'meta': [
        ['og:title', 'CAMISA'],
      ],
    });
    importer.next = Ok(sample);
    await tester.tap(find.byKey(const Key('import-paste-shared')));
    await tester.pumpAndSettle();
    expect(importer.shared.single.url, url);
    expect(importer.previews, [url], reason: 'só o primeiro, pelo link');
    expect(find.text('Camisa de linho'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('import-url')));
    expect(field.controller!.text, url);
  });

  testWidgets('colar no campo o texto do atalho também serve', (tester) async {
    final importer = FakeImporter();
    await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await openImport(
      tester,
      jsonEncode({'fio': 1, 'url': url, 'ld': <String>[]}),
    );
    expect(importer.previews, isEmpty);
    expect(importer.shared.single.url, url);
    expect(find.text('Camisa de linho'), findsOneWidget);
  });

  testWidgets('atalho direto: a peça entra sozinha no Armário', (tester) async {
    final importer = FakeImporter()
      ..inboxItems.add(
        InboxItem(
          id: 'i1',
          preview: ProductPreview(
            storeName: 'Zara',
            url: 'https://www.zara.com/pt/pt/casaco-p1.html',
            viaShortcut: true,
            name: 'CASACO EM PELE',
            brand: 'ZARA',
            description: 'Casaco em pele.',
            material: '100% pele',
            images: const ['https://static.zara.net/a.jpg'],
            variants: const [
              ImportVariant(color: 'Preto', size: 'M'),
              ImportVariant(color: 'Preto', size: 'L'),
            ],
          ),
          createdAt: DateTime(2026),
        ),
      );
    final app = await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await settleUntil(
      tester,
      find.text(
        '1 peça do atalho no Armário. Confirma a categoria e as cores no cartão.',
      ),
    );

    expect(importer.images, ['https://static.zara.net/a.jpg']);
    expect(importer.discarded, ['i1']);
    expect(importer.previews, isEmpty);
    final payload = await created(tester, app.db);
    expect(payload['name'], 'CASACO EM PELE');
    expect(payload['brand'], 'ZARA');
    expect(payload['category'], 'coat');
    expect(
      payload['notes'],
      'Casaco em pele.\n\nCor na loja: Preto\nhttps://www.zara.com/pt/pt/casaco-p1.html',
    );
    final ops = (await tester.runAsync(() => pendingOperations(app.db)))!;
    expect(ops.map((o) => o['kind']), ['create', 'attach_photo']);
    expect(find.byKey(const Key('wardrobe-inbox')), findsNothing);

    // Ao voltar à app vinda do Safari, entram as que chegaram entretanto.
    importer.inboxItems.add(
      InboxItem(id: 'i2', preview: sample, createdAt: DateTime(2026)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleUntil(tester, find.textContaining('1 peça do atalho'));
    expect(importer.discarded, ['i1', 'i2']);
  });

  testWidgets('atalho direto: descartar tira a peça da caixa', (tester) async {
    final importer = FakeImporter();
    await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    // Chegam depois de o Armário ter olhado para a caixa.
    importer.inboxItems.addAll([
      InboxItem(id: 'i1', preview: sample, createdAt: DateTime(2026)),
      InboxItem(id: 'i2', preview: sample, createdAt: DateTime(2026)),
    ]);
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-import')));
    await tester.pumpAndSettle();
    expect(find.text('2 peças enviadas pelo atalho'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-inbox-discard-i2')));
    await tester.pumpAndSettle();
    expect(importer.discarded, ['i2']);
    expect(find.text('1 peça enviada pelo atalho'), findsOneWidget);
  });

  testWidgets('chave do atalho: criar, mostrar uma vez, trocar e desligar', (
    tester,
  ) async {
    final importer = FakeImporter();
    await pumpApp(
      tester,
      overrides: [productImporterProvider.overrideWithValue(importer)],
    );
    await openWardrobe(tester);
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('garment-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-shortcut-setup')));
    await tester.pumpAndSettle();
    expect(
      find.text('Desligado. Cria uma chave para o atalho.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('shortcut-create')));
    await tester.pumpAndSettle();
    expect(find.text('fio_chave1'), findsOneWidget);
    expect(find.text(importer.shortcutEndpoint), findsOneWidget);
    expect(find.text('Ligado. Ainda não foi usado.'), findsOneWidget);

    // Trocar pede confirmação: a chave anterior deixa de servir.
    await tester.tap(find.byKey(const Key('shortcut-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shortcut-replace-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('fio_chave2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shortcut-revoke')));
    await tester.pumpAndSettle();
    expect(find.text('fio_chave2'), findsNothing);
    expect(importer.keyStatus.active, isFalse);

    // Entretanto o atalho mandou uma peça: ao voltar, já aparece.
    importer.inboxItems.add(
      InboxItem(id: 'i1', preview: sample, createdAt: DateTime(2026)),
    );
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.text('1 peça enviada pelo atalho'), findsOneWidget);
  });

  testWidgets('sem Supabase configurado, o botão não aparece', (tester) async {
    await pumpApp(tester);
    await openWardrobe(tester);
    await tester.tap(find.text('Adicionar peça'));
    await settle(tester);
    expect(find.byKey(const Key('garment-import')), findsNothing);
  });
}

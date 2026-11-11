import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/import/data/supabase_product_importer.dart';
import 'package:guarda_roupa/features/import/domain/product_import.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const okBody = {
  'result': 'ok',
  'store': {'id': 'www.zara.com', 'name': 'Zara', 'status': 'works'},
  'url': 'https://www.zara.com/pt/pt/camisa-p1.html',
  'product': {
    'name': 'Camisa de linho',
    'brand': 'Zara',
    'description': 'Camisa de manga comprida.',
    'material': '100% linho',
    'images': [
      'https://static.zara.net/a.jpg',
      'https://static.zara.net/b.jpg',
    ],
    'variants': [
      {'color': 'Branco', 'size': 'M', 'sku': '1'},
      {'color': 'Azul', 'size': 'M', 'image': 'https://static.zara.net/b.jpg'},
    ],
    'sources': {
      'name': 'json-ld',
      'brand': 'microdata',
      'description': 'html',
      'images': 'open-graph',
    },
    'confirm': ['category', 'colors', 'owned', 'variant'],
  },
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

SupabaseProductImporter importer(
  MockClientHandler handler, {
  String? token = 'jwt',
}) => SupabaseProductImporter(
  supabaseUrl: 'https://p.supabase.co',
  apiKey: 'sb_publishable_test',
  accessToken: () => token,
  client: MockClient(handler),
);

void main() {
  test('pré-visualização: campos, fontes e o que confirmar', () {
    final p = ProductPreview.fromJson(okBody)!;
    expect(p.storeName, 'Zara');
    expect(p.siteStatus, SiteStatus.works);
    expect(p.name, 'Camisa de linho');
    expect(p.images, hasLength(2));
    expect(p.variants.last.image, 'https://static.zara.net/b.jpg');
    expect(p.sources['name'], ImportSource.jsonLd);
    expect(p.sources['brand'], ImportSource.microdata);
    expect(p.sources['description'], ImportSource.html);
    expect(p.sources['images'], ImportSource.openGraph);
    expect(
      ProductPreview.fromJson({
        ...okBody,
        'store': {'name': 'loja.example', 'status': 'inventado'},
      })!.siteStatus,
      SiteStatus.newSite,
    );
    expect(p.confirm, contains('variant'));
    expect(ProductPreview.fromJson({'result': 'ok'}), isNull);
  });

  test('para a peça: a variante, o link e os limites', () {
    final p = ProductPreview.fromJson(okBody)!;
    final g = ImportedGarment.from(
      p,
      variant: p.variants.first,
      storeColor: (c) => 'Cor: $c',
      size: (s) => 'Tam: $s',
    );
    expect(g.name, 'Camisa de linho');
    expect(g.brand, 'Zara');
    expect(g.material, '100% linho');
    expect(
      g.notes,
      'Camisa de manga comprida.\n\nCor: Branco\nTam: M\n${p.url}',
    );

    final long = ProductPreview.fromJson({
      ...okBody,
      'product': {'name': 'x' * 300, 'description': 'd' * 3000},
    })!;
    final cut = ImportedGarment.from(
      long,
      storeColor: (c) => c,
      size: (s) => s,
    );
    expect(cut.name, hasLength(80));
    expect(cut.brand, 'Zara', reason: 'sem marca, a loja');
    expect(cut.notes, hasLength(lessThanOrEqualTo(1000)));
    expect(cut.notes, endsWith(long.url), reason: 'o link nunca se corta');
  });

  test('cliente: sessão, apikey e corpo', () async {
    late http.Request sent;
    final result = await importer((r) async {
      sent = r;
      return jsonResponse(okBody);
    }).preview('https://www.zara.com/pt/pt/camisa-p1.html');
    expect(result, isA<Ok<ProductPreview, ImportFailure>>());
    expect(
      sent.url.toString(),
      'https://p.supabase.co/functions/v1/import-product',
    );
    expect(sent.headers['authorization'], 'Bearer jwt');
    expect(sent.headers['apikey'], 'sb_publishable_test');
    expect(jsonDecode(sent.body), {
      'url': 'https://www.zara.com/pt/pt/camisa-p1.html',
    });
  });

  test('cliente: caixa do atalho pela base, com a sessão', () async {
    final sent = <http.Request>[];
    final client = importer((r) async {
      sent.add(r);
      return switch (r.url.pathSegments.last) {
        'list_import_inbox' => jsonResponse([
          {
            'id': 'i1',
            'url': okBody['url'],
            'preview': {...okBody, 'via': 'shared'},
            'created_at': '2026-11-05T10:00:00Z',
          },
          {'id': 'mal', 'preview': 'x', 'created_at': 'x'},
        ]),
        'import_inbox_key_status' => jsonResponse({
          'active': true,
          'created_at': '2026-11-01T10:00:00Z',
          'last_used_at': null,
        }),
        'create_import_inbox_key' => jsonResponse('fio_abc'),
        _ => http.Response('', 204),
      };
    });
    final inbox = await client.inbox();
    final items = (inbox as Ok<List<InboxItem>, ImportFailure>).value;
    expect(items.single.id, 'i1');
    expect(items.single.preview.viaShortcut, isTrue);
    expect(items.single.preview.name, 'Camisa de linho');
    expect(
      sent.single.url.toString(),
      'https://p.supabase.co/rest/v1/rpc/list_import_inbox',
    );
    expect(sent.single.headers['authorization'], 'Bearer jwt');
    expect(sent.single.headers['apikey'], 'sb_publishable_test');

    expect(await client.discardInbox('i1'), isA<Ok<void, ImportFailure>>());
    expect(jsonDecode(sent.last.body), {'p_id': 'i1'});
    final status = await client.shortcutKeyStatus();
    final s = (status as Ok<ShortcutKeyStatus, ImportFailure>).value;
    expect([s.active, s.lastUsedAt], [true, null]);
    expect(await client.createShortcutKey(), isA<Ok<String, ImportFailure>>());
    expect(await client.revokeShortcutKey(), isA<Ok<void, ImportFailure>>());
    expect(
      client.shortcutEndpoint,
      'https://p.supabase.co/functions/v1/import-product?apikey=sb_publishable_test',
    );
  });

  test('cliente: caixa sem sessão ou recusada', () async {
    var calls = 0;
    final none = importer((r) async {
      calls++;
      return jsonResponse([]);
    }, token: null);
    expect(await none.inbox(), isA<Err<List<InboxItem>, ImportFailure>>());
    expect(calls, 0);
    final denied = importer((r) async => jsonResponse({'code': '42501'}, 403));
    expect(
      (await denied.createShortcutKey() as Err).failure,
      isA<NotAllowed>(),
    );
  });

  test('atalho do iPhone: lê só o texto que ele copia', () {
    final page = SharedPage.parse(
      ' {"fio":1,"url":"https://www.zara.com/pt/pt/c-p1.html","title":"CASACO",'
      '"ld":["{}",3],"meta":[["og:title","CASACO"],["x"]]} ',
    )!;
    expect(page.url, 'https://www.zara.com/pt/pt/c-p1.html');
    expect(page.ld, ['{}']);
    expect(page.meta, [('og:title', 'CASACO')]);
    expect(page.toJson(), {
      'title': 'CASACO',
      'ld': ['{}'],
      'meta': [
        ['og:title', 'CASACO'],
      ],
    });
    final withGallery = SharedPage.parse(
      '{"fio":1,"url":"https://www.zara.com/pt/pt/c-p1.html",'
      '"gallery":["https://static.zara.net/a.jpg",7]}',
    )!;
    expect(withGallery.gallery, ['https://static.zara.net/a.jpg']);
    expect(withGallery.toJson()['gallery'], ['https://static.zara.net/a.jpg']);
    expect(SharedPage.parse('https://www.zara.com/pt/pt/c-p1.html'), isNull);
    expect(SharedPage.parse('{"url":"https://a.example"}'), isNull);
    expect(SharedPage.parse('{"fio":1}'), isNull);
    expect(SharedPage.parse('{não é json'), isNull);
  });

  test('cliente: página partilhada vai com o link e os dados', () async {
    late http.Request sent;
    final result =
        await importer((r) async {
          sent = r;
          return jsonResponse({...okBody, 'via': 'shared'});
        }).previewShared(
          const SharedPage(
            url: 'https://www.zara.com/pt/pt/c-p1.html',
            ld: ['{}'],
            meta: [('og:title', 'CASACO')],
          ),
        );
    expect(
      (result as Ok<ProductPreview, ImportFailure>).value.viaShortcut,
      true,
    );
    expect(jsonDecode(sent.body), {
      'url': 'https://www.zara.com/pt/pt/c-p1.html',
      'page': {
        'ld': ['{}'],
        'meta': [
          ['og:title', 'CASACO'],
        ],
      },
    });
  });

  test('cliente: respostas da função viram falhas tipadas', () async {
    Future<ImportFailure> fail(http.Response r) async =>
        switch (await importer((_) async => r).preview('https://x')) {
          Err(:final failure) => failure,
          Ok() => throw StateError('ok'),
        };
    expect(
      await fail(jsonResponse({'result': 'not_public'})),
      isA<NotPublic>(),
    );
    expect(
      await fail(jsonResponse({'result': 'invalid_url'})),
      isA<InvalidLink>(),
    );
    expect(
      await fail(jsonResponse({'result': 'no_metadata'})),
      isA<NoMetadata>(),
    );
    expect(
      await fail(jsonResponse({'result': 'rate_limited'}, 429)),
      isA<RateLimited>(),
    );
    expect(
      await fail(jsonResponse({'result': 'error', 'reason': 'forbidden'}, 403)),
      isA<NotAllowed>(),
    );
    final blocked = await fail(
      jsonResponse({'result': 'fetch_failed', 'reason': 'blocked'}),
    );
    expect((blocked as FetchFailed).reason, 'blocked');
    expect(
      await fail(http.Response('Not found', 404)),
      isA<ImportUnavailable>(),
      reason: 'função ainda não publicada',
    );
  });

  test('cliente: sem sessão não pede nada; rede em baixo', () async {
    var calls = 0;
    final none = await importer((_) async {
      calls++;
      return jsonResponse(okBody);
    }, token: null).preview('https://x');
    expect(none, isA<Err<ProductPreview, ImportFailure>>());
    expect((none as Err).failure, isA<NotAllowed>());
    expect(calls, 0);

    final down = await importer(
      (_) async => throw http.ClientException('offline'),
    ).preview('https://x');
    expect((down as Err).failure, isA<ImportUnavailable>());
  });

  test('cliente: imagem em binário', () async {
    final bytes = [0xff, 0xd8, 0xff, 0x00, 0x80];
    final got = await importer(
      (_) async => http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/jpeg'},
      ),
    ).image('https://static.zara.net/a.jpg');
    expect((got as Ok).value, bytes);

    final refused = await importer(
      (_) async => jsonResponse({'result': 'image_not_offered'}, 403),
    ).image('https://evil.example/a.jpg');
    expect((refused as Err).failure, isA<NotAllowed>());
  });
}

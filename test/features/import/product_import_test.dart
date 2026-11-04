import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/import/data/supabase_product_importer.dart';
import 'package:guarda_roupa/features/import/domain/product_import.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const okBody = {
  'result': 'ok',
  'store': {'id': 'zara', 'name': 'Zara', 'status': 'poc'},
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
    'otherImages': 1,
    'variants': [
      {'color': 'Branco', 'size': 'M', 'sku': '1'},
      {'color': 'Azul', 'size': 'M', 'image': 'https://static.zara.net/b.jpg'},
    ],
    'sources': {'name': 'json-ld', 'brand': 'json-ld', 'images': 'open-graph'},
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
    expect(p.storeInTesting, isTrue);
    expect(p.name, 'Camisa de linho');
    expect(p.images, hasLength(2));
    expect(p.otherImages, 1);
    expect(p.variants.last.image, 'https://static.zara.net/b.jpg');
    expect(p.sources['name'], ImportSource.jsonLd);
    expect(p.sources['images'], ImportSource.openGraph);
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

  test('cliente: respostas da função viram falhas tipadas', () async {
    Future<ImportFailure> fail(http.Response r) async =>
        switch (await importer((_) async => r).preview('https://x')) {
          Err(:final failure) => failure,
          Ok() => throw StateError('ok'),
        };
    expect(
      await fail(jsonResponse({'result': 'unsupported_store'})),
      isA<UnsupportedStore>(),
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
      (_) async => jsonResponse({'result': 'unsupported_store'}),
    ).image('https://evil.example/a.jpg');
    expect((refused as Err).failure, isA<UnsupportedStore>());
  });
}

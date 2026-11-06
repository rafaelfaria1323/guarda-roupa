import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/photo_ai/domain/photo_reader.dart';
import 'package:guarda_roupa/features/stylist/data/supabase_stylist.dart';
import 'package:guarda_roupa/features/stylist/domain/stylist.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  SupabaseStylist stylist(
    http.Response Function(http.Request) respond, {
    String? token = 't',
  }) => SupabaseStylist(
    supabaseUrl: 'https://x.supabase.co',
    apiKey: 'pk',
    accessToken: () => token,
    client: MockClient((req) async => respond(req)),
  );

  http.Response json(int status, Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('manda o pedido com a sessão e lê a escolha', () async {
    late http.Request sent;
    final result = await stylist((req) {
      sent = req;
      return json(200, {
        'name': 'Dia de chuva',
        'why': 'Quente e prático.',
        'items': [
          {'id': 'p1', 'role': 'main_top'},
          {'id': 'p2', 'role': 'bottom'},
        ],
      });
    }).suggest({'garments': <Object>[], 'ask': 'sem ténis'});
    expect(sent.url.toString(), 'https://x.supabase.co/functions/v1/stylist');
    expect(sent.headers['authorization'], 'Bearer t');
    expect(sent.headers['apikey'], 'pk');
    expect(jsonDecode(sent.body), {'garments': <Object>[], 'ask': 'sem ténis'});
    final reply = (result as Ok<StylistReply, PhotoReadFailure>).value;
    expect(reply.items, [('p1', 'main_top'), ('p2', 'bottom')]);
    expect(reply.name, 'Dia de chuva');
  });

  test('erros', () async {
    Future<PhotoReadFailure?> fail(
      http.Response r, {
      String? token = 't',
    }) async => switch (await stylist((_) => r, token: token).suggest({})) {
      Err(:final failure) => failure,
      Ok() => null,
    };
    expect(
      await fail(json(503, {'error': 'not_configured'})),
      PhotoReadFailure.notConfigured,
    );
    expect(
      await fail(json(403, {'error': 'forbidden'})),
      PhotoReadFailure.notAllowed,
    );
    expect(await fail(json(429, {'error': 'busy'})), PhotoReadFailure.busy);
    expect(
      await fail(json(429, {'error': 'rate_limited'})),
      PhotoReadFailure.limit,
    );
    expect(await fail(http.Response('x', 502)), PhotoReadFailure.failed);
    expect(await fail(json(200, {}), token: null), PhotoReadFailure.notAllowed);
  });
}

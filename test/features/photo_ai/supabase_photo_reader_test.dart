import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/core/domain/result.dart';
import 'package:guarda_roupa/features/photo_ai/data/supabase_photo_reader.dart';
import 'package:guarda_roupa/features/photo_ai/domain/photo_reader.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_attributes.dart';
import 'package:guarda_roupa/features/wardrobe/domain/garment_category.dart';
import 'package:guarda_roupa/features/wardrobe/domain/reference_color.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final jpeg = Uint8List.fromList([1, 2, 3, 4]);

  SupabasePhotoReader reader(
    http.Response Function(http.Request) respond, {
    String? token = 't',
  }) => SupabasePhotoReader(
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

  test('peça: envia a foto com a sessão e lê só valores conhecidos', () async {
    late http.Request sent;
    final result = await reader((req) {
      sent = req;
      return json(200, {
        'category': 'shirt',
        'name': 'Camisa às riscas',
        'colors': [
          {'color': 'white', 'share': 60},
          {'color': 'roxo', 'share': 10},
          {'color': 'navy', 'share': 40},
        ],
        'pattern': 'stripes',
        'texture': null,
        'warmth': 'light',
        'formality': 'quase',
      });
    }).readGarment(jpeg);

    expect(
      sent.url.toString(),
      'https://x.supabase.co/functions/v1/describe-photo',
    );
    expect(sent.headers['authorization'], 'Bearer t');
    expect(sent.headers['apikey'], 'pk');
    expect(jsonDecode(sent.body), {
      'kind': 'garment',
      'image': base64Encode(jpeg),
      'mime': 'image/jpeg',
    });
    final reading = (result as Ok<GarmentReading, PhotoReadFailure>).value;
    expect(reading.category, GarmentCategory.shirt);
    expect(reading.name, 'Camisa às riscas');
    expect(
      [for (final c in reading.colors) ReferenceColor.fromRgb(c.rgb)],
      [ReferenceColor.white, ReferenceColor.navy],
    );
    expect([for (final c in reading.colors) c.proportion], [0.6, 0.4]);
    expect(reading.colors.every((c) => !c.confirmed), isTrue);
    expect(reading.pattern, GarmentPattern.stripes);
    expect(reading.warmth, Warmth.light);
    expect(reading.formality, isNull);

    // Só preenche o que não se sabe.
    final filled = reading.fillUnknown(
      const GarmentAttributes(pattern: GarmentPattern.plain),
    );
    expect(filled.pattern, GarmentPattern.plain);
    expect(filled.warmth, Warmth.light);
  });

  test('etiqueta: várias fotos num só pedido', () async {
    Object? sent;
    final result = await reader((req) {
      sent = jsonDecode(req.body);
      return json(200, {
        'found': 'care_label',
        'wash': 'machine_40',
        'tumble_dry': false,
        'material': '100% algodão',
        'care': null,
      });
    }).readLabel([jpeg, jpeg]);
    expect((sent! as Map)['images'], hasLength(2));
    expect((sent! as Map).containsKey('image'), isFalse);
    final label = (result as Ok<LabelReading, PhotoReadFailure>).value;
    expect(label.found, LabelFound.careLabel);
    expect(label.wash, WashCare.machine40);
    expect(label.tumbleDry, isFalse);
    expect(label.material, '100% algodão');
    expect(label.care, isNull);
    expect(label.isEmpty, isFalse);

    final patch = await reader(
      (_) => json(200, {'found': 'brand_or_size_label'}),
    ).readLabel([jpeg]);
    final other = (patch as Ok<LabelReading, PhotoReadFailure>).value;
    expect(other.found, LabelFound.otherLabel);
    expect(other.isEmpty, isTrue);
  });

  test('erros do servidor', () async {
    Future<PhotoReadFailure?> failure(int status, Object body) async =>
        switch (await reader((_) => json(status, body)).readGarment(jpeg)) {
          Err(:final failure) => failure,
          Ok() => null,
        };
    expect(
      await failure(503, {'error': 'not_configured'}),
      PhotoReadFailure.notConfigured,
    );
    expect(
      await failure(403, {'error': 'forbidden'}),
      PhotoReadFailure.notAllowed,
    );
    expect(
      await failure(429, {'error': 'rate_limited'}),
      PhotoReadFailure.limit,
    );
    expect(await failure(429, {'error': 'busy'}), PhotoReadFailure.busy);
    expect(await failure(502, {'error': 'failed'}), PhotoReadFailure.failed);
    expect(
      await reader((_) => http.Response('<html>', 500))
          .readGarment(jpeg)
          .then((r) => (r as Err).failure),
      PhotoReadFailure.failed,
    );
    // Sem sessão nem se chama o servidor.
    var calls = 0;
    final noSession = await reader((_) {
      calls++;
      return json(200, {});
    }, token: null).readLabel([jpeg]);
    expect((noSession as Err).failure, PhotoReadFailure.notAllowed);
    expect(calls, 0);
  });
}

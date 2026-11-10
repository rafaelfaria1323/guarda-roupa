import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/domain/result.dart';
import '../domain/photo_reader.dart';

/// Chama a Edge Function `describe-photo` com a sessão do utilizador. A
/// foto vai em base64 e não fica guardada no servidor.
final class SupabasePhotoReader implements PhotoReader {
  SupabasePhotoReader({
    required String supabaseUrl,
    required this.apiKey,
    required this.accessToken,
    http.Client? client,
  }) : endpoint = Uri.parse('$supabaseUrl/functions/v1/describe-photo'),
       _client = client ?? http.Client();

  final Uri endpoint;
  final String apiKey;

  /// Token da sessão atual; `null` sem sessão.
  final String? Function() accessToken;
  final http.Client _client;

  static const _timeout = Duration(seconds: 40);

  /// Etiquetas: um modelo mais lento e, se falhar, outro (ver o servidor).
  static const _labelTimeout = Duration(seconds: 90);

  @override
  Future<Result<GarmentReading, PhotoReadFailure>> readGarment(
    Uint8List jpeg,
  ) async =>
      switch (await _post('garment', {'image': base64Encode(jpeg)}, _timeout)) {
        Ok(:final value) => Ok(GarmentReading.fromJson(value)),
        Err(:final failure) => Err(failure),
      };

  @override
  Future<Result<LabelReading, PhotoReadFailure>> readLabel(
    List<Uint8List> jpegs,
  ) async => switch (await _post('label', {
    'images': [for (final j in jpegs.take(maxLabelPhotos)) base64Encode(j)],
  }, _labelTimeout)) {
    Ok(:final value) => Ok(LabelReading.fromJson(value)),
    Err(:final failure) => Err(failure),
  };

  Future<Result<Map<String, Object?>, PhotoReadFailure>> _post(
    String kind,
    Map<String, Object> photos,
    Duration timeout,
  ) async {
    final token = accessToken();
    if (token == null) return const Err(PhotoReadFailure.notAllowed);
    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'authorization': 'Bearer $token',
              'apikey': apiKey,
              'content-type': 'application/json',
            },
            body: jsonEncode({'kind': kind, ...photos, 'mime': 'image/jpeg'}),
          )
          .timeout(timeout);
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        return const Err(PhotoReadFailure.failed);
      }
      if (json is! Map<String, Object?>) {
        return const Err(PhotoReadFailure.failed);
      }
      if (response.statusCode == 200) return Ok(json);
      return Err(failureOf(response.statusCode, json['error']));
    } on Object {
      return const Err(PhotoReadFailure.failed);
    }
  }

  static PhotoReadFailure failureOf(int status, Object? error) =>
      switch ((status, error)) {
        (503, _) => PhotoReadFailure.notConfigured,
        (401 || 403, _) => PhotoReadFailure.notAllowed,
        (429, 'busy') => PhotoReadFailure.busy,
        (429, _) => PhotoReadFailure.limit,
        _ => PhotoReadFailure.failed,
      };
}

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

  @override
  Future<Result<GarmentReading, PhotoReadFailure>> readGarment(
    Uint8List jpeg,
  ) async => switch (await _post('garment', jpeg)) {
    Ok(:final value) => Ok(GarmentReading.fromJson(value)),
    Err(:final failure) => Err(failure),
  };

  @override
  Future<Result<LabelReading, PhotoReadFailure>> readLabel(
    Uint8List jpeg,
  ) async => switch (await _post('label', jpeg)) {
    Ok(:final value) => Ok(LabelReading.fromJson(value)),
    Err(:final failure) => Err(failure),
  };

  Future<Result<Map<String, Object?>, PhotoReadFailure>> _post(
    String kind,
    Uint8List jpeg,
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
            body: jsonEncode({
              'kind': kind,
              'image': base64Encode(jpeg),
              'mime': 'image/jpeg',
            }),
          )
          .timeout(_timeout);
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

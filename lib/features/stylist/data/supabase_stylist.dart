import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/domain/result.dart';
import '../../photo_ai/data/supabase_photo_reader.dart';
import '../../photo_ai/domain/photo_reader.dart';
import '../../shopping/domain/shopping_advice.dart';
import '../domain/stylist.dart';

/// Chama a Edge Function `stylist` com a sessão do utilizador. Só vai texto
/// das peças (nada de fotos). Também dá as ideias de compra
/// (`kind: shopping`).
final class SupabaseStylist implements Stylist, ShoppingAdvisor {
  SupabaseStylist({
    required String supabaseUrl,
    required this.apiKey,
    required this.accessToken,
    http.Client? client,
  }) : endpoint = Uri.parse('$supabaseUrl/functions/v1/stylist'),
       _client = client ?? http.Client();

  final Uri endpoint;
  final String apiKey;

  /// Token da sessão atual; `null` sem sessão.
  final String? Function() accessToken;
  final http.Client _client;

  static const _timeout = Duration(seconds: 40);

  @override
  Future<Result<StylistReply, PhotoReadFailure>> suggest(
    Map<String, Object?> brief,
  ) async => switch (await _post(brief)) {
    Ok(:final value) => Ok(StylistReply.fromJson(value)),
    Err(:final failure) => Err(failure),
  };

  @override
  Future<Result<List<ShoppingIdea>, PhotoReadFailure>> advise(
    Map<String, Object?> brief,
  ) async => switch (await _post(brief)) {
    Ok(:final value) => Ok([
      for (final i in value['ideas'] is List ? value['ideas']! as List : [])
        ?ShoppingIdea.fromJson(i),
    ]),
    Err(:final failure) => Err(failure),
  };

  Future<Result<Map<String, Object?>, PhotoReadFailure>> _post(
    Map<String, Object?> brief,
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
            body: jsonEncode(brief),
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
      return Err(
        SupabasePhotoReader.failureOf(response.statusCode, json['error']),
      );
    } on Object {
      return const Err(PhotoReadFailure.failed);
    }
  }
}

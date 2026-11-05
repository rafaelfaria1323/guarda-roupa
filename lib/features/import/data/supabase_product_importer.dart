import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/domain/result.dart';
import '../domain/product_import.dart';

/// Chama a Edge Function `import-product` com a sessão do utilizador.
///
/// Com `http` e não `functions.invoke`: as imagens vêm em binário com o
/// tipo da imagem, que o cliente de funções descodificaria como texto.
final class SupabaseProductImporter implements ProductImporter {
  SupabaseProductImporter({
    required String supabaseUrl,
    required this.apiKey,
    required this.accessToken,
    http.Client? client,
  }) : endpoint = Uri.parse('$supabaseUrl/functions/v1/import-product'),
       _client = client ?? http.Client();

  final Uri endpoint;
  final String apiKey;

  /// Token da sessão atual; `null` sem sessão.
  final String? Function() accessToken;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<http.Response?> _post(Map<String, Object?> body) async {
    final token = accessToken();
    if (token == null) return null;
    return _client
        .post(
          endpoint,
          headers: {
            'authorization': 'Bearer $token',
            'apikey': apiKey,
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
  }

  @override
  Future<Result<ProductPreview, ImportFailure>> preview(String url) =>
      _preview({'url': url});

  @override
  Future<Result<ProductPreview, ImportFailure>> previewShared(
    SharedPage page,
  ) => _preview({'url': page.url, 'page': page.toJson()});

  Future<Result<ProductPreview, ImportFailure>> _preview(
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _post(body);
      if (response == null) return const Err(NotAllowed());
      final json = _json(response);
      if (json == null) return Err(_status(response.statusCode));
      if (json['result'] == 'ok') {
        final preview = ProductPreview.fromJson(json);
        return preview == null ? const Err(ImportUnavailable()) : Ok(preview);
      }
      return Err(_failure(json, response.statusCode));
    } on Object {
      return const Err(ImportUnavailable());
    }
  }

  @override
  Future<Result<Uint8List, ImportFailure>> image(String url) async {
    try {
      final response = await _post({'image': url});
      if (response == null) return const Err(NotAllowed());
      final type = response.headers['content-type'] ?? '';
      if (response.statusCode == 200 && type.startsWith('image/')) {
        return Ok(response.bodyBytes);
      }
      final json = _json(response);
      return Err(
        json == null
            ? _status(response.statusCode)
            : _failure(json, response.statusCode),
      );
    } on Object {
      return const Err(ImportUnavailable());
    }
  }

  static Map<String, Object?>? _json(http.Response r) {
    if (!(r.headers['content-type'] ?? '').contains('application/json')) {
      return null;
    }
    try {
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      return data is Map ? data.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  static ImportFailure _status(int status) => switch (status) {
    401 || 403 => const NotAllowed(),
    429 => const RateLimited(),
    _ => const ImportUnavailable(),
  };

  static ImportFailure _failure(Map<String, Object?> json, int status) =>
      switch (json['result']) {
        'not_public' => const NotPublic(),
        'invalid_url' => const InvalidLink(),
        'no_metadata' => const NoMetadata(),
        'rate_limited' => const RateLimited(),
        'fetch_failed' => FetchFailed(json['reason'] as String?),
        _ => _status(status),
      };
}

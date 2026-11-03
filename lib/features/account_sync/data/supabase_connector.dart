import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'operation_upload_queue.dart';

final class SupabaseOperationUploader implements OperationUploader {
  const SupabaseOperationUploader(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, Object?>> apply(Map<String, Object?> operation) async {
    final response = await _client.rpc<Object?>(
      'apply_garment_operation',
      params: {'op': operation},
    );
    if (response is Map<String, Object?>) return response;
    throw StateError('Resposta inesperada de apply_garment_operation');
  }
}

/// Liga o PowerSync à sessão Supabase: o token da sessão autentica o
/// PowerSync (Supabase Auth) e as operações vão por RPC.
final class SupabasePowerSyncConnector extends PowerSyncBackendConnector {
  SupabasePowerSyncConnector({
    required this._client,
    required this._powerSyncUrl,
  }) : _queue = OperationUploadQueue(SupabaseOperationUploader(_client));

  final SupabaseClient _client;
  final String _powerSyncUrl;
  final OperationUploadQueue _queue;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    var session = _client.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      session = (await _client.auth.refreshSession()).session;
      if (session == null) return null;
    }
    return PowerSyncCredentials(
      endpoint: _powerSyncUrl,
      token: session.accessToken,
      userId: session.user.id,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) =>
      _queue.upload(database);
}

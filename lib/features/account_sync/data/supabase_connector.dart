import 'dart:typed_data';

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../wardrobe/domain/garment_photo.dart';
import '../../wardrobe/domain/photo_storage.dart';
import 'operation_upload_queue.dart';
import 'supabase_photo_storage.dart';

final class SupabaseOperationUploader implements OperationUploader {
  const SupabaseOperationUploader(this._client, this._storage);

  final SupabaseClient _client;
  final PhotoStorage _storage;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sem sessão');
    return id;
  }

  @override
  Future<void> uploadPhotoFile(
    String photoId,
    PhotoVariant variant,
    Uint8List bytes,
  ) => _storage.upload(PhotoRules.storagePath(_uid, photoId, variant), bytes);

  @override
  Future<void> removePhotoFiles(String photoId) => _storage.remove([
    for (final v in PhotoVariant.values)
      PhotoRules.storagePath(_uid, photoId, v),
  ]);

  @override
  Future<Map<String, Object?>> apply(Map<String, Object?> operation) async {
    final response = await _client.rpc<Object?>(
      'apply_garment_operation',
      params: {'op': operation},
    );
    if (response is Map<String, Object?>) return response;
    throw StateError('Resposta inesperada de apply_garment_operation');
  }

  @override
  Future<Map<String, Object?>> applyWear(Map<String, Object?> operation) async {
    final response = await _client.rpc<Object?>(
      'apply_wear_operation',
      params: {'op': operation},
    );
    if (response is Map<String, Object?>) return response;
    throw StateError('Resposta inesperada de apply_wear_operation');
  }

  @override
  Future<Map<String, Object?>> applyOutfit(
    Map<String, Object?> operation,
  ) async {
    final response = await _client.rpc<Object?>(
      'apply_outfit_operation',
      params: {'op': operation},
    );
    if (response is Map<String, Object?>) return response;
    throw StateError('Resposta inesperada de apply_outfit_operation');
  }

  @override
  Future<Map<String, Object?>> applyStyle(
    Map<String, Object?> operation,
  ) async {
    final response = await _client.rpc<Object?>(
      'apply_style_operation',
      params: {'op': operation},
    );
    if (response is Map<String, Object?>) return response;
    throw StateError('Resposta inesperada de apply_style_operation');
  }
}

/// Liga o PowerSync à sessão Supabase: o token da sessão autentica o
/// PowerSync (Supabase Auth) e as operações vão por RPC.
final class SupabasePowerSyncConnector extends PowerSyncBackendConnector {
  SupabasePowerSyncConnector({
    required this._client,
    required this._powerSyncUrl,
  }) : _queue = OperationUploadQueue(
         SupabaseOperationUploader(_client, SupabasePhotoStorage(_client)),
       );

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

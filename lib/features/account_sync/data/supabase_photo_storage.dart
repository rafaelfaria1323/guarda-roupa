import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../wardrobe/domain/photo_storage.dart';

/// Bucket privado `garment-photos` (ver migração 20261104000002).
final class SupabasePhotoStorage implements PhotoStorage {
  const SupabasePhotoStorage(this._client);

  static const bucket = 'garment-photos';

  final SupabaseClient _client;

  StorageFileApi get _files => _client.storage.from(bucket);

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    // upsert: repetir depois de uma falha a meio não é erro. Os ficheiros
    // são imutáveis (id novo por foto), por isso o conteúdo é o mesmo.
    await _files.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
        cacheControl: '31536000',
      ),
    );
  }

  @override
  Future<Uint8List> download(String path) => _files.download(path);

  @override
  Future<void> remove(List<String> paths) => _files.remove(paths);

  @override
  Future<Uri> temporaryLink(String path) async =>
      Uri.parse(await _files.createSignedUrl(path, 600));
}

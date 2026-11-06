import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../account_sync/application/providers.dart';
import '../domain/garment.dart';
import '../domain/garment_photo.dart';
import '../domain/photo_storage.dart';
import '../domain/wardrobe_repository.dart';
import 'photo_providers.dart';

/// Mais uma unidade igual (Duplicar): os mesmos dados e as mesmas
/// fotografias, copiadas com ids novos (cada peça pode depois ter as
/// suas, e apagar uma não apaga as fotos da outra). Uma foto que não
/// está neste dispositivo descarrega-se; sem rede fica de fora.
Future<WardrobeResult<Garment>> duplicateWithPhotos(
  WidgetRef ref,
  WardrobeRepository repo,
  Garment source,
) =>
    // Lidos antes de esperar: quem chama pode fechar entretanto.
    duplicateGarmentWithPhotos(
      repo,
      source,
      storage: ref.read(photoStorageProvider),
      userId: ref.read(currentUserProvider).value?.id,
    );

Future<WardrobeResult<Garment>> duplicateGarmentWithPhotos(
  WardrobeRepository repo,
  Garment source, {
  required PhotoStorage? storage,
  required String? userId,
}) async {
  Future<Uint8List?> bytes(GarmentPhoto photo, PhotoVariant variant) async {
    final local = await repo.photoBytes(photo.id, variant);
    if (local != null) return local;
    if (storage == null || userId == null) return null;
    try {
      final remote = await storage.download(
        PhotoRules.storagePath(userId, photo.id, variant),
      );
      if (variant == PhotoVariant.main &&
          sha256.convert(remote).toString() != photo.sha256) {
        return null;
      }
      return remote;
    } on Object {
      return null;
    }
  }

  var result = await repo.duplicateGarment(source.id);
  final copy = switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };
  if (copy == null) return result;
  for (final photo in source.photos) {
    final main = await bytes(photo, PhotoVariant.main);
    final thumb = await bytes(photo, PhotoVariant.thumb);
    if (main == null || thumb == null) continue;
    final added = await repo.addPhoto(
      copy.id,
      ProcessedPhoto(
        width: photo.width,
        height: photo.height,
        main: main,
        thumb: thumb,
        sha256: photo.sha256,
      ),
    );
    if (added is Ok) result = added;
  }
  return result;
}

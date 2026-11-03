import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../data/image_picker_photo_picker.dart';
import '../data/photo_processor.dart';
import '../domain/garment_photo.dart';
import '../domain/photo_picker.dart';
import '../domain/photo_storage.dart';

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const ImagePickerPhotoPicker(),
);

final photoProcessorProvider =
    Provider<Future<PhotoProcessing> Function(Uint8List)>(
      (ref) => processPhoto,
    );

/// Storage privado; `null` = sem cloud (fotos só neste dispositivo).
final photoStorageProvider = Provider<PhotoStorage?>((ref) => null);

/// Bytes de uma foto: da cache local ou, se faltarem, descarregados do
/// Storage e guardados para funcionar offline a seguir. `null` = ainda
/// indisponível (sem rede ou sem cloud).
final photoBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, (GarmentPhoto, PhotoVariant)>((ref, key) async {
      final (photo, variant) = key;
      final repo = ref.watch(wardrobeRepositoryProvider);
      if (repo == null) return null;
      final local = await repo.photoBytes(photo.id, variant);
      if (local != null) return local;

      final storage = ref.watch(photoStorageProvider);
      final userId = ref.watch(currentUserProvider).value?.id;
      if (storage == null || userId == null) return null;
      final bytes = await storage.download(
        PhotoRules.storagePath(userId, photo.id, variant),
      );
      if (variant == PhotoVariant.main &&
          sha256.convert(bytes).toString() != photo.sha256) {
        throw StateError('Fotografia corrompida');
      }
      await repo.cachePhotoBytes(photo.id, variant, bytes);
      return bytes;
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/model_store.dart';
import '../data/onnx_background_remover.dart';
import '../domain/background_remover.dart';
import '../domain/local_model.dart';

final modelStoreProvider = Provider<ModelStore>((ref) => createModelStore());

/// Estado de um modelo neste dispositivo; descarregar só quando o
/// utilizador pede.
final localModelProvider =
    NotifierProvider.family<LocalModelNotifier, ModelState, LocalModel>(
      LocalModelNotifier.new,
    );

class LocalModelNotifier extends Notifier<ModelState> {
  LocalModelNotifier(this.model);

  final LocalModel model;

  @override
  ModelState build() {
    _check();
    return const ModelChecking();
  }

  Future<void> _check() async {
    bool ready;
    try {
      ready = await ref.read(modelStoreProvider).isReady(model);
    } on Object {
      ready = false; // sem armazenamento: como se não houvesse modelo
    }
    if (!ref.mounted || state is! ModelChecking) return;
    state = ready ? const ModelReady() : const ModelAbsent();
  }

  Future<void> download() async {
    if (state is ModelDownloading || state is ModelReady) return;
    state = const ModelDownloading(0);
    try {
      await ref
          .read(modelStoreProvider)
          .download(
            model,
            onProgress: (p) {
              if (ref.mounted) state = ModelDownloading(p.clamp(0, 1));
            },
          );
      if (ref.mounted) state = const ModelReady();
    } on Object {
      if (ref.mounted) state = const ModelAbsent(failed: true);
    }
  }

  Future<void> remove() async {
    if (state is ModelDownloading) return;
    try {
      await ref.read(modelStoreProvider).remove(model);
    } on Object {
      // Fica como estava; o utilizador pode tentar de novo.
      return;
    }
    if (ref.mounted) state = const ModelAbsent();
  }
}

/// Recorte de fundo, ou `null` sem o modelo neste dispositivo (as cores
/// seguem pela borda da foto).
final backgroundRemoverProvider = Provider<BackgroundRemover?>((ref) {
  final model = LocalModels.background;
  final ready = ref.watch(
    localModelProvider(model).select((s) => s is ModelReady),
  );
  if (!ready) return null;
  final remover = OnnxBackgroundRemover(ref.watch(modelStoreProvider), model);
  ref.onDispose(remover.close);
  return remover;
});

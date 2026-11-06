import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_sync/application/providers.dart';
import '../data/model_store.dart';
import '../data/onnx_background_remover.dart';
import '../data/onnx_category_suggester.dart';
import '../data/onnx_image_embedder.dart';
import '../domain/background_remover.dart';
import '../domain/category_suggester.dart';
import '../domain/image_embedder.dart';
import '../domain/local_model.dart';
import 'similar_garments_finder.dart';

final modelStoreProvider = Provider<ModelStore>((ref) => createModelStore());

/// Estado de um modelo neste dispositivo. Descarrega-se sozinho com a
/// primeira peça com foto (`ModelsAutoDownload`) ou a pedido nas
/// Definições.
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

/// FashionCLIP (encoder de imagem), ou `null` sem o modelo neste
/// dispositivo.
final imageEmbedderProvider = Provider<ImageEmbedder?>((ref) {
  final model = LocalModels.category;
  final ready = ref.watch(
    localModelProvider(model).select((s) => s is ModelReady),
  );
  if (!ready) return null;
  final embedder = OnnxImageEmbedder(ref.watch(modelStoreProvider), model);
  ref.onDispose(embedder.close);
  return embedder;
});

/// Sugestão de categoria pela foto, ou `null` sem o modelo neste
/// dispositivo (o botão não aparece).
final categorySuggesterProvider = Provider<CategorySuggester?>((ref) {
  final embedder = ref.watch(imageEmbedderProvider);
  return embedder == null ? null : EmbeddingCategorySuggester(embedder);
});

/// Peças parecidas com uma imagem, ou `null` sem o modelo ou sem conta.
final similarGarmentsFinderProvider = Provider<SimilarGarmentsFinder?>((ref) {
  final embedder = ref.watch(imageEmbedderProvider);
  final db = ref.watch(userDatabaseProvider).value;
  final repo = ref.watch(wardrobeRepositoryProvider);
  if (embedder == null || db == null || repo == null) return null;
  return SimilarGarmentsFinder(embedder, db, repo);
});

/// Descarregar sozinho com a primeira peça com foto (decisão do utilizador
/// a 2026-11-06). Os testes desligam-no: não há rede.
final localAiAutoDownloadEnabledProvider = Provider<bool>((_) => true);

/// O utilizador removeu um modelo neste dispositivo: daí em diante só se
/// descarrega a pedido. `null` enquanto a base local abre.
final localAiAutoOptOutProvider =
    AsyncNotifierProvider<LocalAiAutoOptOut, bool?>(LocalAiAutoOptOut.new);

class LocalAiAutoOptOut extends AsyncNotifier<bool?> {
  static const _key = 'local_ai_auto_off';

  @override
  Future<bool?> build() async {
    final db = ref.watch(userDatabaseProvider).value;
    if (db == null) return null;
    final row = await db.getOptional(
      'SELECT value FROM local_settings WHERE key = ?',
      [_key],
    );
    return row?['value'] == '1';
  }

  Future<void> set({required bool optedOut}) async {
    final db = ref.read(userDatabaseProvider).value;
    if (db == null) return;
    await db.execute(
      'INSERT OR REPLACE INTO local_settings (key, value) VALUES (?, ?)',
      [_key, optedOut ? '1' : '0'],
    );
    if (ref.mounted) state = AsyncData(optedOut);
  }
}

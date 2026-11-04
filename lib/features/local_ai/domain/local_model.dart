/// Um modelo de IA local (docs/features/ia-local.md): os pesos não vão no
/// repositório nem na app. Descarregam-se só com o acordo do utilizador e
/// confirmam-se pelo sha256 antes de se usar.
final class LocalModel {
  const LocalModel({
    required this.id,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.license,
  });

  final String id;
  final String fileName;

  /// Origem nas apps nativas. Na Web vem do próprio site (`models/`), porque
  /// o browser só aceita outra origem com CORS.
  final Uri url;
  final String sha256;
  final int bytes;
  final String license;
}

abstract final class LocalModels {
  /// U²-Netp (recorte de fundo), na versão ONNX publicada pelo `rembg`.
  /// Pesos Apache-2.0 (xuebinqin/U-2-Net).
  static final background = LocalModel(
    id: 'u2netp',
    fileName: 'u2netp.onnx',
    url: Uri.parse(
      'https://github.com/danielgatis/rembg/releases/download/v0.0.0/'
      'u2netp.onnx',
    ),
    sha256: '309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8',
    bytes: 4574861,
    license: 'Apache-2.0',
  );
}

/// O modelo neste dispositivo.
sealed class ModelState {
  const ModelState();
}

final class ModelChecking extends ModelState {
  const ModelChecking();
}

/// Por descarregar. [failed]: a última tentativa falhou (sem rede,
/// interrompida ou ficheiro diferente do esperado).
final class ModelAbsent extends ModelState {
  const ModelAbsent({this.failed = false});
  final bool failed;
}

/// [progress] de 0 a 1.
final class ModelDownloading extends ModelState {
  const ModelDownloading(this.progress);
  final double progress;
}

final class ModelReady extends ModelState {
  const ModelReady();
}

/// Onde ficam os modelos neste dispositivo.
abstract interface class ModelStore {
  Future<bool> isReady(LocalModel model);

  /// Descarrega e confirma o sha256; só depois o modelo fica pronto. Falha
  /// (exceção) sem deixar nada a meio.
  Future<void> download(
    LocalModel model, {
    required void Function(double progress) onProgress,
  });

  Future<void> remove(LocalModel model);

  /// Caminho (nativo) ou URL (Web) para o runtime abrir o modelo.
  Future<String> location(LocalModel model);
}

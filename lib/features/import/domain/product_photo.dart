import 'dart:typed_data';

/// Quanto uma foto mostra só a peça (sem pessoa): acima do limiar do
/// [ProductPhotoScorer] conta como "só a peça". `null` se não conseguir.
typedef ProductPhotoScore = Future<double?> Function(Uint8List bytes);

/// Avalia fotos da loja com a IA local; `null` sem o modelo neste
/// dispositivo.
abstract interface class ProductPhotoScorer {
  /// A partir daqui a foto conta como "só a peça".
  double get threshold;

  Future<double?> score(Uint8List bytes);
}

/// A foto escolhida e os bytes já copiados (não se copia duas vezes).
typedef PickedPhoto = ({String url, Uint8List bytes});

/// Quantas fotos da loja se olham, no máximo: cada cópia gasta quota.
const productPhotoTries = 4;

/// Escolhe a foto da loja que mostra só a peça, para a capa não ser o
/// manequim (decisão do utilizador a 2026-11-07).
///
/// Sem [scorer], copia só a primeira, como antes. Com ele, copia pela ordem
/// da página até [productPhotoTries] fotos e pára na primeira que passe do
/// limiar. Se nenhuma passar, fica a mais "sozinha" se for pelo menos
/// neutra (≥ 0); senão a primeira. As fotos que falham contam como vistas.
/// [fetched] recebe todas as copiadas, para quem quiser reaproveitar.
Future<PickedPhoto?> pickProductPhoto(
  List<String> urls, {
  required Future<Uint8List?> Function(String url) fetch,
  ProductPhotoScorer? scorer,
  void Function(String url, Uint8List bytes)? fetched,
}) async {
  if (urls.isEmpty) return null;
  if (scorer == null) {
    final bytes = await fetch(urls.first);
    if (bytes == null) return null;
    fetched?.call(urls.first, bytes);
    return (url: urls.first, bytes: bytes);
  }
  PickedPhoto? first;
  PickedPhoto? best;
  var bestScore = double.negativeInfinity;
  for (final url in urls.take(productPhotoTries)) {
    final bytes = await fetch(url);
    if (bytes == null) continue;
    fetched?.call(url, bytes);
    final photo = (url: url, bytes: bytes);
    first ??= photo;
    final s = await scorer.score(bytes);
    if (s == null) continue;
    if (s >= scorer.threshold) return photo;
    if (s > bestScore) {
      bestScore = s;
      best = photo;
    }
  }
  return best != null && bestScore >= 0 ? best : first;
}

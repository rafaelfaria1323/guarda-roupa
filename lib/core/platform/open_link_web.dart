import 'package:web/web.dart' as web;

/// Abre o link num separador novo do navegador.
Future<bool> openLink(Uri uri) async {
  web.window.open(uri.toString(), '_blank', 'noopener');
  return true;
}

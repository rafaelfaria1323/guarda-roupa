/// O que este aparelho permite.
enum PushSupport {
  /// Pode receber notificações.
  available,

  /// iPhone/iPad no Safari: só com a app no ecrã principal.
  needsInstall,

  /// Este navegador (ou a app fora da Web) não recebe notificações.
  unsupported,
}

enum PushPermission { granted, denied, prompt }

/// A subscrição deste aparelho no serviço de push do navegador.
final class PushSubscriptionKeys {
  const PushSubscriptionKeys({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}

/// As notificações do navegador (Web Push). Fora da Web não há nada.
abstract interface class PushClient {
  PushSupport get support;
  PushPermission get permission;

  /// O fuso do aparelho ("Europe/Lisbon").
  String get timeZone;

  /// Pede autorização. Tem de ser chamado logo no toque do utilizador (no
  /// iPhone, depois de esperar pela rede já não conta como toque).
  Future<PushPermission> requestPermission();

  /// A subscrição atual deste aparelho, se houver.
  Future<PushSubscriptionKeys?> current();

  /// Subscreve (ou devolve a subscrição que já existe) com a chave pública
  /// do servidor. `null` se o navegador recusou.
  Future<PushSubscriptionKeys?> subscribe(String serverPublicKey);

  Future<void> unsubscribe();

  /// Caminhos da app abertos ao tocar numa notificação com a app aberta.
  Stream<String> get openedPaths;
}

/// Fora da Web (e nos testes, por omissão).
final class UnsupportedPushClient implements PushClient {
  const UnsupportedPushClient();

  @override
  PushSupport get support => PushSupport.unsupported;
  @override
  PushPermission get permission => PushPermission.denied;
  @override
  String get timeZone => 'Europe/Lisbon';
  @override
  Future<PushPermission> requestPermission() async => PushPermission.denied;
  @override
  Future<PushSubscriptionKeys?> current() async => null;
  @override
  Future<PushSubscriptionKeys?> subscribe(String serverPublicKey) async => null;
  @override
  Future<void> unsubscribe() async {}
  @override
  Stream<String> get openedPaths => const Stream.empty();
}

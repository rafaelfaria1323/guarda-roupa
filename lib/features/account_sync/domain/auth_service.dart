/// Utilizador autenticado.
final class AuthUser {
  const AuthUser({required this.id, this.email});
  final String id;
  final String? email;
}

/// Autenticação, independente do fornecedor (Supabase + Google, P-02).
abstract interface class AuthService {
  AuthUser? get currentUser;

  /// Emite sempre que a sessão muda (entrada, saída, expiração).
  Stream<AuthUser?> get userChanges;

  Future<void> signInWithGoogle();

  Future<void> signOut();
}

/// Usado quando a configuração do Supabase não foi fornecida: a app mostra
/// esse estado em vez de fingir que o login funciona.
final class UnconfiguredAuthService implements AuthService {
  const UnconfiguredAuthService();

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get userChanges => const Stream.empty();

  @override
  Future<void> signInWithGoogle() =>
      Future.error(StateError('Supabase não configurado'));

  @override
  Future<void> signOut() async {}
}

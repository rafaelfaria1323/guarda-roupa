import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../app/config.dart';
import '../domain/auth_service.dart';

final class SupabaseAuthService implements AuthService {
  const SupabaseAuthService(this._client);

  final SupabaseClient _client;

  static AuthUser? _map(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);

  @override
  AuthUser? get currentUser => _map(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get userChanges =>
      _client.auth.onAuthStateChange.map((state) => _map(state.session?.user));

  @override
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      // Na Web volta à origem de onde saiu (localhost ou Cloudflare Pages;
      // ambas em Redirect URLs do Supabase); no Android, pelo deep link.
      redirectTo: kIsWeb
          ? '${Uri.base.origin}/'
          : AppConfig.androidAuthRedirect,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

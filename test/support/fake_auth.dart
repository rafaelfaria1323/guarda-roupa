import 'dart:async';

import 'package:guarda_roupa/features/account_sync/domain/auth_service.dart';

/// Autenticação em memória: entra e sai sem rede.
final class FakeAuthService implements AuthService {
  FakeAuthService({this._user});

  AuthUser? _user;
  final _changes = StreamController<AuthUser?>.broadcast();
  int signInCalls = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get userChanges => _changes.stream;

  void emit(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  @override
  Future<void> signInWithGoogle() async {
    signInCalls++;
    emit(const AuthUser(id: 'user-a', email: 'a@example.com'));
  }

  @override
  Future<void> signOut() async => emit(null);
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'powersync/powersync.dart';

part 'supabase.g.dart';

loadSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
}

@riverpod
Stream<Session?> session(Ref ref) {
  final instance = Supabase.instance.client.auth;

  return instance.onAuthStateChange
      .map((_) => instance.currentSession)
      .startWith(instance.currentSession);
}

@riverpod
bool isLoggedIn(Ref ref) {
  return ref.watch(sessionProvider.select((session) => session.value != null));
}

@riverpod
String? userId(Ref ref) {
  return ref.watch(sessionProvider.select((session) => session.value?.user.id));
}

typedef AuthState = ({String? error, bool isBusy});

@riverpod
final class AuthNotifier extends _$AuthNotifier {
  static final _logger = Logger('AuthNotifier');

  @override
  AuthState build() {
    return (error: null, isBusy: false);
  }

  Future<void> _doWork(Future<void> Function() inner) async {
    try {
      state = (error: null, isBusy: true);
      await inner();
      state = (error: null, isBusy: false);
    } catch (e, s) {
      _logger.warning('auth error', e, s);
      state = (error: e.toString(), isBusy: false);
    }
  }

  Future<void> login(String username, String password) {
    return _doWork(() async {
      await Supabase.instance.client.auth
          .signInWithPassword(email: username, password: password);
    });
  }

  Future<void> signup(String username, String password) async {
    return _doWork(() async {
      await Supabase.instance.client.auth
          .signUp(email: username, password: password);
    });
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    await (await ref.read(powerSyncInstanceProvider.future))
        .disconnectAndClear();
  }
}

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'navigation.gr.dart';
import 'supabase.dart';

export 'navigation.gr.dart';

@AutoRouterConfig()
final class AppRouter extends RootStackRouter {
  final _AuthGuard _authGuard;

  AppRouter(Ref ref) : _authGuard = _AuthGuard(ref);

  @override
  RouteType get defaultRouteType => const RouteType.material();

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: LoginRoute.page),
        AutoRoute(page: SignupRoute.page),
        AutoRoute(
          initial: true,
          page: ListsRoute.page,
          guards: [_authGuard],
        ),
      ];
}

final class _AuthGuard extends AutoRouteGuard {
  final Ref _ref;

  _AuthGuard(this._ref);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (_ref.read(isLoggedInProvider)) {
      resolver.next(true);
    } else {
      resolver.redirectUntil(const LoginRoute());
    }
  }
}

final appRouter = Provider((ref) => AppRouter(ref));

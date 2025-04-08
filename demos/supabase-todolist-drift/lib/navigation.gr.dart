// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i4;
import 'package:supabase_todolist_drift/screens/lists.dart' as _i1;
import 'package:supabase_todolist_drift/screens/login.dart' as _i2;
import 'package:supabase_todolist_drift/screens/signup.dart' as _i3;

/// generated route for
/// [_i1.ListsPage]
class ListsRoute extends _i4.PageRouteInfo<void> {
  const ListsRoute({List<_i4.PageRouteInfo>? children})
    : super(ListsRoute.name, initialChildren: children);

  static const String name = 'ListsRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i1.ListsPage();
    },
  );
}

/// generated route for
/// [_i2.LoginPage]
class LoginRoute extends _i4.PageRouteInfo<void> {
  const LoginRoute({List<_i4.PageRouteInfo>? children})
    : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i2.LoginPage();
    },
  );
}

/// generated route for
/// [_i3.SignupPage]
class SignupRoute extends _i4.PageRouteInfo<void> {
  const SignupRoute({List<_i4.PageRouteInfo>? children})
    : super(SignupRoute.name, initialChildren: children);

  static const String name = 'SignupRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i3.SignupPage();
    },
  );
}

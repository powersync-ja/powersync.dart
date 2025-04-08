// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i8;
import 'package:flutter/material.dart' as _i9;
import 'package:supabase_todolist_drift/navigation.dart' as _i5;
import 'package:supabase_todolist_drift/screens/add_item_dialog.dart' as _i1;
import 'package:supabase_todolist_drift/screens/add_list_dialog.dart' as _i2;
import 'package:supabase_todolist_drift/screens/list_details.dart' as _i3;
import 'package:supabase_todolist_drift/screens/lists.dart' as _i4;
import 'package:supabase_todolist_drift/screens/login.dart' as _i6;
import 'package:supabase_todolist_drift/screens/signup.dart' as _i7;

/// generated route for
/// [_i1.AddItemDialog]
class AddItemRoute extends _i8.PageRouteInfo<AddItemRouteArgs> {
  AddItemRoute({
    _i9.Key? key,
    required String list,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         AddItemRoute.name,
         args: AddItemRouteArgs(key: key, list: list),
         initialChildren: children,
       );

  static const String name = 'AddItemRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AddItemRouteArgs>();
      return _i1.AddItemDialog(key: args.key, list: args.list);
    },
  );
}

class AddItemRouteArgs {
  const AddItemRouteArgs({this.key, required this.list});

  final _i9.Key? key;

  final String list;

  @override
  String toString() {
    return 'AddItemRouteArgs{key: $key, list: $list}';
  }
}

/// generated route for
/// [_i2.AddListDialog]
class AddListRoute extends _i8.PageRouteInfo<void> {
  const AddListRoute({List<_i8.PageRouteInfo>? children})
    : super(AddListRoute.name, initialChildren: children);

  static const String name = 'AddListRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i2.AddListDialog();
    },
  );
}

/// generated route for
/// [_i3.ListsDetailsPage]
class ListsDetailsRoute extends _i8.PageRouteInfo<ListsDetailsRouteArgs> {
  ListsDetailsRoute({
    _i9.Key? key,
    required String list,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         ListsDetailsRoute.name,
         args: ListsDetailsRouteArgs(key: key, list: list),
         initialChildren: children,
       );

  static const String name = 'ListsDetailsRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ListsDetailsRouteArgs>();
      return _i3.ListsDetailsPage(key: args.key, list: args.list);
    },
  );
}

class ListsDetailsRouteArgs {
  const ListsDetailsRouteArgs({this.key, required this.list});

  final _i9.Key? key;

  final String list;

  @override
  String toString() {
    return 'ListsDetailsRouteArgs{key: $key, list: $list}';
  }
}

/// generated route for
/// [_i4.ListsPage]
class ListsRoute extends _i8.PageRouteInfo<void> {
  const ListsRoute({List<_i8.PageRouteInfo>? children})
    : super(ListsRoute.name, initialChildren: children);

  static const String name = 'ListsRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i4.ListsPage();
    },
  );
}

/// generated route for
/// [_i5.LoggedInContents]
class LoggedInRoot extends _i8.PageRouteInfo<void> {
  const LoggedInRoot({List<_i8.PageRouteInfo>? children})
    : super(LoggedInRoot.name, initialChildren: children);

  static const String name = 'LoggedInRoot';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i5.LoggedInContents();
    },
  );
}

/// generated route for
/// [_i6.LoginPage]
class LoginRoute extends _i8.PageRouteInfo<void> {
  const LoginRoute({List<_i8.PageRouteInfo>? children})
    : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i6.LoginPage();
    },
  );
}

/// generated route for
/// [_i7.SignupPage]
class SignupRoute extends _i8.PageRouteInfo<void> {
  const SignupRoute({List<_i8.PageRouteInfo>? children})
    : super(SignupRoute.name, initialChildren: children);

  static const String name = 'SignupRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i7.SignupPage();
    },
  );
}

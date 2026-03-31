import 'dart:ffi';

typedef ExtensionEntrypoint = Int Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>);

@Native<ExtensionEntrypoint>()
// ignore: non_constant_identifier_names
external int sqlite3_powersync_init(
  Pointer<Void> db,
  Pointer<Void> pzErrMsg,
  Pointer<Void> pApi,
);

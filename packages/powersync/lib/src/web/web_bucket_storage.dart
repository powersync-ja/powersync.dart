import 'package:powersync/sqlite_async.dart';
import 'package:powersync/src/bucket_storage.dart';
import 'package:sqlite_async/web.dart';

class WebBucketStorage extends BucketStorage {
  final WebSqliteConnection _webDb;

  WebBucketStorage(this._webDb) : super(_webDb);

  @override

  /// Override to implement the flush parameter for web.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      required bool flush}) async {
    return _webDb.writeTransaction(callback,
        lockTimeout: lockTimeout, flush: flush);
  }
}

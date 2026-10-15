import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';

/// A [Mutex] implemented with [RandomAccessFile.lock].
///
/// This mutex is safe to use across processes, but not for multiple isolates
/// within a single process. It is designed to be used as a global singleton
/// active for the entire lifecycle of a process.
///
/// Note that file locking has platform-specific behavior, which impact this
/// mutex implementation. On POSIX systems for example, this uses advisory
/// locks, which are _per process_. So multiple isolates using a file mutex in
/// the same process would be able to access the critical section concurrently.
final class FileMutex implements Mutex {
  final Directory _directory;
  final String _lockName;

  final Mutex _internal = Mutex.simple();
  RandomAccessFile? _file;

  /// Creates a named mutex in a directory.
  ///
  /// When first acquired, the mutex will create a file named after its name in
  /// the directory. This file is never deleted, so the directory should either
  /// be a temporary or at least an app-local directory.
  FileMutex(this._directory, this._lockName);

  Future<RandomAccessFile> _acquireFileLock() async {
    var file = _file;
    if (file == null) {
      final unopened = File.fromUri(_directory.uri.resolve(_lockName));
      file = _file = await unopened.open(mode: FileMode.append);
    }

    await file.lock(FileLock.blockingExclusive);
    return file;
  }

  Future<void> _releaseFileLock(RandomAccessFile file) {
    return file.unlock();
  }

  @override
  Future<T> lock<T>(
    Future<T> Function() callback, {
    Future<void>? abortTrigger,
  }) {
    return _internal.lock(() async {
      final file = await _acquireFileLock();
      try {
        return await callback();
      } finally {
        await _releaseFileLock(file);
      }
    });
  }

  /// Closes the file descriptor or handle used by this mutex.
  Future<void> close() {
    return _internal.lock(() async {
      if (_file case final file?) {
        await file.close();
      }
    });
  }
}

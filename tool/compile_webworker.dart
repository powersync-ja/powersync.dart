import 'dart:io';

import 'package:path/path.dart' as path;

Future<void> main() async {
  // This should be the package root
  final cwd = Directory.current.absolute.path;
  final repoRoot = path.normalize(cwd);

  /// The monorepo root assets directory
  final workerFilename = 'powersync_db.worker.js';
  final dbWorkerOutputPath =
      path.join(repoRoot, 'packages/powersync/assets/$workerFilename');
  final workerSourcePath =
      path.join(repoRoot, './packages/powersync/lib/src/web/worker.dart');

  // And compile worker code
  final dbWorkerProcess = await Process.run(
      Platform.executable,
      [
        'compile',
        'js',
        '-o',
        dbWorkerOutputPath,
        '-O4',
        workerSourcePath,
      ],
      workingDirectory: cwd);

  if (dbWorkerProcess.exitCode != 0) {
    throw Exception(
        'Could not compile db worker.\nstdout: ${dbWorkerProcess.stdout.toString()}\nstderr: ${dbWorkerProcess.stderr.toString()}');
  }

  // Copy this to all demo apps web folders
  final demosRoot = path.join(repoRoot, 'demos');
  final demoDirectories =
      Directory(demosRoot).listSync().whereType<Directory>().toList();

  for (final demoDir in demoDirectories) {
    // only if the demo is web enabled
    final demoWebDir = path.join(demoDir.absolute.path, 'web');
    if (!Directory(demoWebDir).existsSync()) {
      continue;
    }
    final demoOutputPath = path.join(demoWebDir, workerFilename);
    File(dbWorkerOutputPath).copySync(demoOutputPath);

    final oldSyncWorker =
        File(path.join(demoWebDir, 'powersync_sync.worker.js'));
    if (await oldSyncWorker.exists()) {
      await oldSyncWorker.delete();
      print('Deleted ${oldSyncWorker.path}, the db worker covers that now.');
    }
  }
}

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

  final workerSourcePath = path.join(repoRoot,
      './packages/powersync_core/lib/src/web/powersync_db.worker.dart');

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
        'Could not compile db worker: ${dbWorkerProcess.stdout.toString()}');
  }

  final syncWorkerFilename = 'powersync_sync.worker.js';
  final syncWorkerOutputPath =
      path.join(repoRoot, 'packages/powersync/assets/$syncWorkerFilename');

  final syncWorkerSourcePath = path.join(
      repoRoot, './packages/powersync_core/lib/src/web/sync_worker.dart');

  final syncWorkerProcess = await Process.run(
      Platform.executable,
      [
        'compile',
        'js',
        '-o',
        syncWorkerOutputPath,
        '-O4',
        syncWorkerSourcePath,
      ],
      workingDirectory: cwd);

  if (syncWorkerProcess.exitCode != 0) {
    throw Exception(
        'Could not compile sync worker: ${dbWorkerProcess.stdout.toString()}');
  }

  final workerFile = File(dbWorkerOutputPath);
  final syncWorkerFile = File(syncWorkerOutputPath);

  //Copy workers to powersync_core
  final powersyncCoreAssetsPath =
      path.join(repoRoot, 'packages/powersync_core/assets');
  workerFile.copySync('$powersyncCoreAssetsPath/$workerFilename');
  syncWorkerFile.copySync('$powersyncCoreAssetsPath/$syncWorkerFilename');

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
    File(syncWorkerOutputPath)
        .copySync(path.join(demoWebDir, syncWorkerFilename));
  }
}

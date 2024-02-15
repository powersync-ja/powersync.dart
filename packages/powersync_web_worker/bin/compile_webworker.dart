import 'dart:io';

import 'package:path/path.dart' as path;

Future<void> main() async {
  // This should be the package root
  final cwd = Directory.current.absolute.path;
  final repoRoot = path.normalize(path.join(cwd, '../../'));

  /// The monorepo root assets directory
  final workerFilename = 'powersync_db.worker.js';
  final outputPath = path.join(repoRoot, 'assets/$workerFilename');

  final workerSourcePath = './lib/src/powersync_db.worker.dart';

  // And compile worker code
  final process = await Process.run(
      Platform.executable,
      [
        'compile',
        'js',
        '-o',
        outputPath,
        '-O4',
        workerSourcePath,
      ],
      workingDirectory: cwd);

  if (process.exitCode != 0) {
    throw Exception('Could not compile worker: ${process.stdout.toString()}');
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
    File(outputPath).copySync(demoOutputPath);
  }
}

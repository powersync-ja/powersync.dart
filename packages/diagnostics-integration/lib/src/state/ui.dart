import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter_riverpod/legacy.dart';

final darkModeEnabled = ChangeNotifierProvider(
  (_) => extensionManager.darkThemeEnabled,
);

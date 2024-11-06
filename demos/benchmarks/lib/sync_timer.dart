import 'dart:async';

import 'package:powersync/powersync.dart';

class SyncTimer {
  Stopwatch stopwatch = Stopwatch();
  Duration? syncTime;
  bool hasSynced = false;
  StreamSubscription? subscription;

  StreamSubscription start(PowerSyncDatabase db) {
    hasSynced = false;
    syncTime = null;
    subscription?.cancel();
    stopwatch.reset();

    stopwatch.start();
    subscription = db.statusStream.listen((data) {
      if (hasSynced != true &&
          data.hasSynced == true &&
          data.connected == true &&
          data.downloading == false) {
        syncTime = stopwatch.elapsed;
        hasSynced = true;
      }
    });
    return subscription!;
  }

  Duration get elapsed {
    return stopwatch.elapsed;
  }
}

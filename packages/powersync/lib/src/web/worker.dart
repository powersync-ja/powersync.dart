/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync/lib/src/web/worker.dart -o assets/powersync_db.worker.js
/// The output should then be included in each project's `web` directory
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:web/web.dart';

import 'sync_worker.dart';
import 'worker_utils.dart';

final _isSharedWorker = globalContext.has('SharedWorkerGlobalScope');
final _isDedicatedWorker = globalContext.has('DedicatedWorkerGlobalScope');

void main() {
  final controller = PowerSyncAsyncSqliteController();
  final connector =
      PowerSyncWorkerConnector((globalContext as Window).location.href);
  final messagesForDatabaseWorker = StreamController<MessageEvent>(sync: true);

  WebSqlite.workerEntrypoint(
    controller: controller,
    environment: _Environment(connector, messagesForDatabaseWorker.stream),
  );

  if (_isSharedWorker) {
    final syncWorker = SyncWorker();

    void handleMessage(MessageEvent event) {
      final message = event.data as SharedWorkerMessage;

      if (message.isForSyncWorker) {
        syncWorker.trackPort(message.message as MessagePort);
      } else {
        messagesForDatabaseWorker.add(
          MessageEvent(
            'message',
            MessageEventInit(data: message.message),
          ),
        );
      }
    }

    void handlePort(MessagePort port) {
      port.start();
      EventStreamProviders.messageEvent.forTarget(port).listen(handleMessage);
    }

    EventStreamProviders.connectEvent
        .forTarget(globalContext as SharedWorkerGlobalScope)
        .listen((event) {
      for (final port in (event as MessageEvent).ports.toDart) {
        handlePort(port);
      }
    });
  } else {
    EventStreamProviders.messageEvent
        .forTarget(globalContext as DedicatedWorkerGlobalScope)
        .listen(messagesForDatabaseWorker.add);
  }
}

final class _Environment implements WorkerEnvironment {
  @override
  final PowerSyncWorkerConnector connector;

  @override
  final Stream<MessageEvent> incomingMessages;

  _Environment(this.connector, this.incomingMessages);

  @override
  void close() {
    // Don't close shared workers when sqlite3_web asks us to: The worker is
    // also used for sync, not just for databases. So we shouldn't close it
    // just because a database has been closed.
    if (_isDedicatedWorker) {
      (globalContext as DedicatedWorkerGlobalScope).close();
    }
  }
}

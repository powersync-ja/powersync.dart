import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:web/web.dart';

import 'sync_worker.dart';
import 'worker_utils.dart';

final _isSharedWorker = globalContext.has('SharedWorkerGlobalScope');

void main() {
  final controller = PowerSyncAsyncSqliteController();
  final connector = PowerSyncWorkerConnector(Uri.base);
  final messagesForDatabaseWorker = StreamController<MessageEvent>(sync: true);
  final syncWorker = SyncWorker();

  WebSqlite.workerEntrypoint(
    controller: controller,
    environment: _Environment(connector, messagesForDatabaseWorker.stream),
  );

  void handleMessage(MessageEvent event) {
    final message = event.data as PowerSyncWorkerMessage;

    if (message.isForSyncWorker) {
      final data = message.message;
      if (!_isSharedWorker) {
        print('Ignoring sync worker message to dedicated worker.');
        return;
      }

      syncWorker.trackPort(data as MessagePort);
    } else {
      messagesForDatabaseWorker.add(
        MessageEvent(
          'message',
          MessageEventInit(data: message.message),
        ),
      );
    }
  }

  if (_isSharedWorker) {
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
        .listen(handleMessage);
  }
}

final class _Environment implements WorkerEnvironment {
  @override
  final PowerSyncWorkerConnector connector;

  @override
  final Stream<MessageEvent> incomingMessages;

  _Environment(this.connector, this.incomingMessages);
}

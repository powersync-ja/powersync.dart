import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'server/sync_server/mock_sync_server.dart';

void main() {
  late TestHttpServerHelper testServer;

  setUp(() async {
    testServer = TestHttpServerHelper();
    await testServer.start();
  });

  tearDown(() async {
    await testServer.stop();
  });

  test('should receive events from the sync stream without waiting for close',
      () async {
    final client = http.Client();
    final request =
        http.Request('POST', testServer.uri.replace(path: '/sync/stream'));
    request.headers['Content-Type'] = 'application/json';

    // Send the request and get the response stream
    final responseStream = await client.send(request);

    final expectedEvents = ['event1', 'event2', 'event3'];
    final receivedEvents = <String>[];
    final completer = Completer<void>();

    // Listen to the response stream for real-time processing of incoming events
    final subscription = responseStream.stream
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen(
      (event) {
        receivedEvents.add(event);
        if (receivedEvents.length == expectedEvents.length) {
          completer.complete(); // Complete once all events are received
        }
      },
      onError: (e) => completer.completeError(e),
    );

    // Programmatically trigger events on the server
    for (final event in expectedEvents) {
      testServer.addEvent('$event\n');
      await Future.delayed(
          Duration(milliseconds: 100)); // Small delay for each event
    }

    // Wait for the events to be received
    await completer.future.timeout(Duration(seconds: 5));
    await subscription.cancel();
    client.close();

    expect(receivedEvents.toSet().containsAll(expectedEvents.toSet()), isTrue);
  });
}

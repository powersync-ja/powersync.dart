@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:powersync/src/web/http/client.dart';
import 'package:powersync/src/web/sync_worker_protocol.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show MessageChannel;

void main() {
  final uri = Uri.parse('https://powersync.com/foo/bar');

  test('can send http requests', () async {
    final (client, _) = await createRemoteClient(MockClient((request) async {
      expect(request.url, uri);
      expect(request.method, 'POST');
      expect(request.headers, containsPair('Foo', 'Bar'));
      expect(request.body, 'body');

      return Response('ok', 200, headers: {'Response': 'Ok'});
    }));

    final response =
        await client.post(uri, headers: {'Foo': 'Bar'}, body: 'body');
    expect(response.statusCode, 200);
    expect(response.headers, {'Response': 'Ok'});
    expect(response.body, 'ok');
  });

  test('response stream control', () async {
    final responseStream = StreamController<Uint8List>();
    final (client, _) =
        await createRemoteClient(MockClient.streaming((request, stream) async {
      await stream.drain<void>();
      return StreamedResponse(responseStream.stream, 200);
    }));

    final response = await client.send(Request('GET', uri));
    expect(responseStream.hasListener, isFalse);

    final receivedChunks = <List<int>>[];
    final sub = response.stream.listen(receivedChunks.add);
    await pumpEventQueue();
    expect(responseStream.hasListener, isTrue);
    expect(responseStream.isPaused, isFalse);

    responseStream.add(Uint8List(123));
    await pumpEventQueue();
    expect(receivedChunks, [hasLength(123)]);

    responseStream.add(Uint8List(42));
    sub.pause();
    await pumpEventQueue();
    expect(responseStream.isPaused, isTrue);

    sub.resume();
    await pumpEventQueue();
    expect(responseStream.isPaused, isFalse);

    sub.cancel();
    await pumpEventQueue();
    expect(responseStream.hasListener, isFalse);
  });

  group('can abort', () {
    test('before receiving response', () async {
      final (client, _) =
          await createRemoteClient(MockClient.streaming((request, _) async {
        await (request as Abortable).abortTrigger!;
        throw RequestAbortedException();
      }));

      await expectLater(
        client.send(AbortableRequest('GET', uri, abortTrigger: Future.value())),
        throwsA(isA<RequestAbortedException>()),
      );
    });

    test('in response', () async {
      final abort = Completer<void>();
      final responseStream = StreamController<Uint8List>();
      var aborted = false;

      final (client, _) =
          await createRemoteClient(MockClient.streaming((request, _) async {
        (request as Abortable).abortTrigger!.whenComplete(() {
          aborted = true;
          responseStream
            ..addError(RequestAbortedException())
            ..close();
        });
        return StreamedResponse(responseStream.stream, 200);
      }));

      final response = await client
          .send(AbortableRequest('GET', uri, abortTrigger: abort.future));
      responseStream.add(Uint8List(42));
      final receivedResponseStream = StreamQueue(response.stream);
      await expectLater(receivedResponseStream, emits(hasLength(42)));

      abort.complete();
      await expectLater(
          receivedResponseStream, emitsError(isA<RequestAbortedException>()));
      expect(aborted, isTrue);
    });

    test('via stream cancel', () async {
      final responseStream = StreamController<Uint8List>();

      final (client, _) =
          await createRemoteClient(MockClient.streaming((request, _) async {
        return StreamedResponse(responseStream.stream, 200);
      }));

      final response = await client.send(AbortableRequest('GET', uri));
      responseStream.add(Uint8List(42));

      final receivedResponseStream = StreamQueue(response.stream);
      await expectLater(receivedResponseStream, emits(hasLength(42)));
      await receivedResponseStream.cancel();
      await pumpEventQueue();
      expect(responseStream.hasListener, isFalse);
    });
  });

  group('reacts to closed channel', () {
    test('before receiving response', () async {
      late Client client;
      late WorkerCommunicationChannel channel;

      (client, channel) =
          await createRemoteClient(MockClient.streaming((request, _) async {
        channel.close();
        return StreamedResponse(Stream.empty(), 200);
      }));

      await expectLater(client.send(AbortableRequest('GET', uri)),
          throwsA(isA<ChannelClosedException>()));
    });

    test('in response stream', () async {
      final responseStream = StreamController<Uint8List>();
      final (client, channel) =
          await createRemoteClient(MockClient.streaming((request, _) async {
        return StreamedResponse(responseStream.stream, 200);
      }));

      final response = await client.send(AbortableRequest('GET', uri));
      responseStream.add(Uint8List(42));
      final receivedResponseStream = StreamQueue(response.stream);
      await expectLater(receivedResponseStream, emits(hasLength(42)));

      final expectation = expectLater(
          receivedResponseStream, emitsError(isA<ChannelClosedException>()));
      await pumpEventQueue();
      channel.close();
      await expectation;
    });
  });
}

Future<(Client, WorkerCommunicationChannel)> createRemoteClient(
    Client original) async {
  final channel = MessageChannel();

  final local = WorkerCommunicationChannel(
    port: channel.port1,
    requestHandler: (type, payload) async {
      throw UnimplementedError();
    },
    exposedHttpClient: original,
  );
  final remote = WorkerCommunicationChannel(
    port: channel.port2,
    requestHandler: (type, payload) async {
      throw UnimplementedError();
    },
  );
  local.observeRemoteLockName(await remote.lockName);
  remote.observeRemoteLockName(await local.lockName);

  return (RemoteHttpClient(remote), local);
}

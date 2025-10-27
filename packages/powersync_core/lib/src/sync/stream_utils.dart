import 'dart:async';

import 'dart:convert' as convert;
import 'dart:math';
import 'dart:typed_data';

import 'package:typed_data/typed_buffers.dart';

import '../exceptions.dart';

/// Inject a broadcast stream into a normal stream.
Stream<T> addBroadcast<T>(Stream<T> a, Stream<T> broadcast) {
  assert(broadcast.isBroadcast);
  return mergeStreams([a, broadcast]);
}

/// This is similar in functionality to rxdart's MergeStream.
/// The resulting stream emits values from either stream, as soon as they are
/// received.
///
/// One difference is that if _any_ of the streams are closed, the resulting
/// stream is closed.
Stream<T> mergeStreams<T>(List<Stream<T>> streams) {
  final controller = StreamController<T>(sync: true);

  List<StreamSubscription<T>>? subscriptions;
  var isClosing = false;

  controller.onListen = () {
    subscriptions = streams.map((stream) {
      return stream.listen(
        (event) {
          return controller.add(event);
        },
        onError: controller.addError,
        onDone: () async {
          if (!isClosing) {
            isClosing = true;

            try {
              await cancelAll(subscriptions!);
            } catch (e, s) {
              controller.addError(e, s);
            } finally {
              controller.close();
            }
          }
        },
      );
    }).toList();
  };

  controller.onCancel = () {
    if (subscriptions != null && !isClosing) {
      // Important: The Future must be returned here.
      // Since calling cancel on one of the subscriptions may error,
      // not returning the Future may result in an unhandled error.
      return cancelAll(subscriptions!);
    }
  };

  controller.onPause = () {
    if (subscriptions != null) {
      return pauseAll(subscriptions!);
    }
  };

  controller.onResume = () {
    if (subscriptions != null) {
      return resumeAll(subscriptions!);
    }
  };

  return controller.stream;
}

extension ByteStreamToLines on Stream<List<int>> {
  /// Decodes this stream using UTF8 and then splits the text stream by
  /// newlines.
  Stream<String> get lines {
    final textInput = transform(convert.utf8.decoder);
    return textInput.transform(const convert.LineSplitter());
  }

  /// Splits this stream into BSON documents without parsing them.
  Stream<Uint8List> get bsonDocuments {
    return Stream.eventTransformed(this, _BsonSplittingSink.new);
  }
}

extension StreamToJson on Stream<String> {
  Stream<Object?> get parseJson {
    return map(convert.jsonDecode);
  }
}

void pauseAll(List<StreamSubscription<void>> subscriptions) {
  for (var sub in subscriptions) {
    sub.pause();
  }
}

void resumeAll(List<StreamSubscription<void>> subscriptions) {
  for (var sub in subscriptions) {
    sub.resume();
  }
}

Future<void> cancelAll(List<StreamSubscription<void>> subscriptions) async {
  final futures = subscriptions.map((sub) => sub.cancel());
  await Future.wait(futures);
}

/// A variant of [Stream.fromFuture] that makes [StreamSubscription.cancel]
/// await the original future and report errors.
///
/// When using the regular [Stream.fromFuture], cancelling the subscription
/// before the future completes with an error could cause an unhandled error to
/// be reported.
/// Further, it could cause concurrency issues in the stream client because it
/// was possible for us to:
///
///  1. Make an HTTP request, wrapped in [Stream.fromFuture] to later expand
///     sync lines from the response.
///  2. Receive a cancellation request, posting an event on another stream that
///     is merged into the pending HTTP stream.
///  3. Act on the cancellation request by cancelling the merged subscription.
///  4. As a clean-up action, close the HTTP client (while the request is still
///     being resolved).
///
/// Running step 4 and 1 concurrently is really bad, so we delay the
/// cancellation until step 1 has completed.
///
/// As a further discussion, note that throwing in [StreamSubscription.cancel]
/// is also not exactly a good practice. However, it is the only way to properly
/// delay cancelling streams here, since the [future] itself is a critical
/// operation that must complete first here.
Stream<T> streamFromFutureAwaitInCancellation<T>(Future<T> future) {
  final controller = StreamController<T>(sync: true);
  var cancelled = false;

  final handledFuture = future.then((value) {
    controller
      ..add(value)
      ..close();
  }, onError: (Object error, StackTrace trace) {
    if (cancelled) {
      // Make handledFuture complete with the error, so that controller.cancel
      // throws (instead of the error being unhandled).
      throw error;
    } else {
      controller
        ..addError(error, trace)
        ..close();
    }
  });

  controller.onCancel = () async {
    cancelled = true;
    await handledFuture;
  };

  return controller.stream;
}

/// An [EventSink] that takes raw bytes as inputs, buffers them internally by
/// reading a 4-byte length prefix for each message and then emits them as
/// chunks.
final class _BsonSplittingSink implements EventSink<List<int>> {
  final EventSink<Uint8List> _downstream;

  final length = ByteData(4);
  int remainingBytes = 4;

  Uint8Buffer? pendingBuffer;

  _BsonSplittingSink(this._downstream);

  @override
  void add(List<int> data) {
    var i = 0;
    while (i < data.length) {
      final availableInData = data.length - i;

      if (pendingBuffer case final pending?) {
        // We're in the middle of reading a document
        final bytesToRead = min(availableInData, remainingBytes);
        pending.addAll(data, i, i + bytesToRead);
        i += bytesToRead;
        remainingBytes -= bytesToRead;
        assert(remainingBytes >= 0);

        if (remainingBytes == 0) {
          _downstream.add(pending.buffer
              .asUint8List(pending.offsetInBytes, pending.lengthInBytes));

          // Prepare reading another document, starting with its length
          pendingBuffer = null;
          remainingBytes = 4;
        }
      } else {
        final bytesToRead = min(availableInData, remainingBytes);
        final lengthAsUint8List = length.buffer.asUint8List();

        lengthAsUint8List.setRange(
          4 - remainingBytes,
          4 - remainingBytes + bytesToRead,
          data,
          i,
        );
        i += bytesToRead;
        remainingBytes -= bytesToRead;
        assert(remainingBytes >= 0);

        if (remainingBytes == 0) {
          // Transition from reading length header to reading document.
          // Subtracting 4 because the length of the header is included in the
          // length.
          remainingBytes = length.getInt32(0, Endian.little) - 4;
          if (remainingBytes < 5) {
            _downstream.addError(
              PowerSyncProtocolException(
                  'Invalid length for bson: $remainingBytes'),
              StackTrace.current,
            );
          }

          pendingBuffer = Uint8Buffer()..addAll(lengthAsUint8List);
        }
      }
    }

    assert(i == data.length);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _downstream.addError(error, stackTrace);
  }

  @override
  void close() {
    if (pendingBuffer != null || remainingBytes != 4) {
      _downstream.addError(
        PowerSyncProtocolException('Pending data when stream was closed'),
        StackTrace.current,
      );
    }

    _downstream.close();
  }
}

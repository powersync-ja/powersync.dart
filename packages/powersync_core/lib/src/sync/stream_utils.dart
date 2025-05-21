import 'dart:async';

import 'dart:convert' as convert;

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

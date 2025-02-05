import 'dart:async';

import 'package:http/http.dart';
import 'dart:convert' as convert;

/// Inject a broadcast stream into a normal stream.
Stream<T> addBroadcast<T>(Stream<T> a, Stream<T> broadcast) {
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

  controller.onListen = () {
    subscriptions = streams.map((stream) {
      return stream.listen((event) {
        return controller.add(event);
      }, onDone: () {
        controller.close();
      }, onError: controller.addError);
    }).toList();
  };

  controller.onCancel = () {
    if (subscriptions != null) {
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

/// Given a raw ByteStream, parse each line as JSON.
Stream<Object?> ndjson(ByteStream input) {
  final textInput = input.transform(convert.utf8.decoder);
  final lineInput = textInput.transform(const convert.LineSplitter());
  final jsonInput = lineInput.transform(
      StreamTransformer.fromHandlers(handleError: (error, stackTrace, sink) {
    /// On Web if the connection is closed, this error will throw, but
    /// the stream is never closed. This closes the stream on error.
    sink.close();
  }, handleData: (String data, EventSink<dynamic> sink) {
    sink.add(convert.jsonDecode(data));
  }));
  return jsonInput;
}

/// Given a raw ByteStream, parse each line as JSON.
Stream<String> newlines(ByteStream input) {
  final textInput = input.transform(convert.utf8.decoder);
  final lineInput = textInput.transform(const convert.LineSplitter());
  return lineInput;
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

import 'dart:async';

import 'package:http/http.dart';
import 'dart:convert' as convert;

/// Inject a broadcast stream into another stream.
Stream<T> addBroadcast<T>(Stream<T> a, Stream<T> broadcast) {
  var controller = StreamController<T>();

  StreamSubscription<T>? sub1;
  StreamSubscription<T>? sub2;

  void close() {
    controller.close();
    sub1!.cancel();
    sub2!.cancel();
  }

  // TODO: backpressure?
  sub1 = a.listen((event) {
    controller.add(event);
  }, onDone: () {
    close();
  }, onError: (e) {
    controller.addError(e);
    close();
  });

  sub2 = broadcast.listen((event) {
    controller.add(event);
  }, onDone: () {
    close();
  }, onError: (e) {
    controller.addError(e);
    close();
  });

  controller.onCancel = () {
    sub1?.cancel();
  };

  return controller.stream;
}

/// Given a raw ByteStream, parse each line as JSON.
Stream<Object?> ndjson(ByteStream input) {
  final textInput = input.transform(convert.utf8.decoder);
  final lineInput = textInput.transform(const convert.LineSplitter());
  final jsonInput = lineInput.transform(StreamTransformer.fromHandlers(
      handleData: (String data, EventSink<dynamic> sink) {
    sink.add(convert.jsonDecode(data));
  }));
  return jsonInput;
}

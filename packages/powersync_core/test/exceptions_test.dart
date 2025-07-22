import 'dart:convert';

import 'package:http/http.dart';
import 'package:powersync_core/src/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('SyncResponseException', () {
    const errorResponse =
        '{"error":{"code":"PSYNC_S2106","status":401,"description":"Authentication required","name":"AuthorizationError"}}';

    test('fromStreamedResponse', () async {
      final exc = await SyncResponseException.fromStreamedResponse(
          StreamedResponse(Stream.value(utf8.encode(errorResponse)), 401));

      expect(exc.statusCode, 401);
      expect(exc.description,
          'Request failed: PSYNC_S2106(AuthorizationError): Authentication required');
    });

    test('fromResponse', () {
      final exc =
          SyncResponseException.fromResponse(Response(errorResponse, 401));
      expect(exc.statusCode, 401);
      expect(exc.description,
          'Request failed: PSYNC_S2106(AuthorizationError): Authentication required');
    });

    test('malformed', () {
      const malformed =
          '{"message":"Route GET:/foo/bar not found","error":"Not Found","statusCode":404}';

      final exc = SyncResponseException.fromResponse(Response(malformed, 401));
      expect(exc.statusCode, 401);
      expect(exc.description,
          'Request failed: {"message":"Route GET:/foo/bar not found","error":"Not Found","statusCode":404}');

      final exc2 = SyncResponseException.fromResponse(Response(
          'not even json', 500,
          reasonPhrase: 'Internal server error'));
      expect(exc2.statusCode, 500);
      expect(exc2.description, 'Internal server error');
    });
  });
}

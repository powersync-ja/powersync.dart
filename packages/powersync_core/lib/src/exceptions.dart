import 'dart:async';
import 'dart:convert' as convert;

import 'package:http/http.dart' as http;

/// This indicates an error with configured credentials.
class CredentialsException implements Exception {
  String message;

  CredentialsException(this.message);

  @override
  toString() {
    return 'CredentialsException: $message';
  }
}

/// An internal protocol exception.
///
/// This indicates that the server sent an invalid response.
class PowerSyncProtocolException implements Exception {
  String message;

  PowerSyncProtocolException(this.message);

  @override
  toString() {
    return 'SyncProtocolException: $message';
  }
}

/// An error that received from the sync service.
///
/// Examples include authorization errors (401) and temporary service issues (503).
class SyncResponseException implements Exception {
  /// Parse an error response from the PowerSync service
  static Future<SyncResponseException> fromStreamedResponse(
      http.StreamedResponse response) async {
    try {
      final body = await response.stream.bytesToString();
      return _fromResponseBody(response, body);
    } on Exception catch (_) {
      // Could be FormatException, stream issues, or possibly other exceptions.
      // Fallback to just using the response header.
      return _fromResponseHeader(response);
    }
  }

  /// Parse an error response from the PowerSync service
  static SyncResponseException fromResponse(http.Response response) {
    try {
      final body = response.body;
      return _fromResponseBody(response, body);
    } on Exception catch (_) {
      // Could be FormatException, or possibly other exceptions.
      // Fallback to just using the response header.
      return _fromResponseHeader(response);
    }
  }

  static SyncResponseException _fromResponseBody(
      http.BaseResponse response, String body) {
    final decoded = convert.jsonDecode(body);
    final details = _stringOrFirst(decoded['error']?['details']) ?? body;
    final message = '${response.reasonPhrase ?? "Request failed"}: $details';
    return SyncResponseException(response.statusCode, message);
  }

  static SyncResponseException _fromResponseHeader(http.BaseResponse response) {
    return SyncResponseException(
      response.statusCode,
      response.reasonPhrase ?? "Request failed",
    );
  }

  int statusCode;
  String description;

  SyncResponseException(this.statusCode, this.description);

  @override
  toString() {
    return 'SyncResponseException: $statusCode $description';
  }
}

String? _stringOrFirst(Object? details) {
  if (details == null) {
    return null;
  } else if (details is String) {
    return details;
  } else if (details case [final String first, ...]) {
    return first;
  } else {
    return null;
  }
}

class PowersyncNotReadyException implements Exception {
  /// @nodoc
  PowersyncNotReadyException(this.message);

  final String message;
}

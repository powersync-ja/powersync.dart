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
    final details = switch (decoded['error']) {
          final Map<String, Object?> details => _errorDescription(details),
          _ => null,
        } ??
        body;

    final message = '${response.reasonPhrase ?? "Request failed"}: $details';
    return SyncResponseException(response.statusCode, message);
  }

  static SyncResponseException _fromResponseHeader(http.BaseResponse response) {
    return SyncResponseException(
      response.statusCode,
      response.reasonPhrase ?? "Request failed",
    );
  }

  /// Extracts an error description from an error resonse looking like
  /// `{"code":"PSYNC_S2106","status":401,"description":"Authentication required","name":"AuthorizationError"}`.
  static String? _errorDescription(Map<String, Object?> raw) {
    final code = raw['code']; // Required, string
    final description = raw['description']; // Required, string

    final name = raw['name']; // Optional, string
    final details = raw['details']; // Optional, string

    if (code is! String || description is! String) {
      return null;
    }

    final fullDescription = StringBuffer(code);
    if (name is String) {
      fullDescription.write('($name)');
    }

    fullDescription
      ..write(': ')
      ..write(description);

    if (details is String) {
      fullDescription
        ..write(', ')
        ..write(details);
    }

    return fullDescription.toString();
  }

  int statusCode;
  String description;

  SyncResponseException(this.statusCode, this.description);

  @override
  toString() {
    return 'SyncResponseException: $statusCode $description';
  }
}

class PowersyncNotReadyException implements Exception {
  /// @nodoc
  PowersyncNotReadyException(this.message);

  final String message;
}

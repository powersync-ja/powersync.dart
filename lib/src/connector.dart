import './powersync_database.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Implement this to connect an app backend.
///
/// The connector is responsible for:
/// 1. Creating PowerSync credentials.
/// 2. Applying local changes on the server.
///
/// [DevConnector] is provided as a quick starting point, without user management
/// or significant security.
///
/// For production, use a custom implementation.
abstract class PowerSyncBackendConnector {
  /// Get credentials for PowerSync.
  ///
  /// Return null if no credentials are available.
  ///
  /// This token is kept for the duration of a sync connection.
  ///
  /// If the sync connection is interrupted, new credentials will be requested.
  /// The credentials may be cached - in that case, make sure to refresh when
  /// [refreshCredentials] is called.
  Future<PowerSyncCredentials?> getCredentials();

  /// Refresh credentials.
  ///
  /// This may be called pro-actively before new credentials are required,
  /// allowing time to refresh credentials without adding a delay to the next
  /// connection.
  Future<void> refreshCredentials() async {}

  /// Upload local changes to the app backend.
  ///
  /// Use [PowerSyncDatabase.getCrudBatch] to get a batch of changes to upload.
  Future<void> uploadData(PowerSyncDatabase database);
}

/// Temporary credentials to connect to the PowerSync service.
class PowerSyncCredentials {
  /// PowerSync endpoint, e.g. "https://myinstance.powersync.co".
  final String endpoint;

  /// Temporary token to authenticate against the service.
  final String token;

  /// User ID.
  final String? userId;

  /// When the token expires.
  final DateTime? expiresAt;

  const PowerSyncCredentials(
      {required this.endpoint,
      required this.token,
      required this.userId,
      required this.expiresAt});

  factory PowerSyncCredentials.fromJson(Map<String, dynamic> parsed) {
    String token = parsed['token'];
    DateTime? expiresAt = getExpiryDate(token);

    return PowerSyncCredentials(
        endpoint: parsed['endpoint'],
        token: parsed['token'],
        userId: parsed['user_id'],
        expiresAt: expiresAt);
  }

  /// Whether credentials have expired.
  bool expired() {
    if (expiresAt == null) {
      return false;
    }
    if (expiresAt!.difference(DateTime.now()) < const Duration(seconds: 0)) {
      return true;
    }
    return false;
  }

  /// Whether credentials will soon (within a minute).
  ///
  /// When this time is reached, refresh refresh the credentials.
  bool expiresSoon() {
    if (expiresAt == null) {
      return false;
    }
    if (expiresAt!.difference(DateTime.now()) < const Duration(minutes: 1)) {
      return true;
    }
    return false;
  }

  /// Get an expiry date from a JWT token, if specified.
  ///
  /// The token is not validated in any way.
  static DateTime? getExpiryDate(String token) {
    try {
      List<String> parts = token.split('.');
      if (parts.length == 3) {
        final rawData = base64Decode(parts[1]);
        final text = Utf8Decoder().convert(rawData);
        Map<String, dynamic> payload = jsonDecode(text);
        if (payload.containsKey('exp') && payload['exp'] is int) {
          return DateTime.fromMillisecondsSinceEpoch(payload['exp'] * 1000);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  toString() {
    return "PowerSyncCredentials<endpoint: $endpoint userId: $userId expiresAt: $expiresAt>";
  }

  /// Resolve an endpoint path against the endpoint URI.
  Uri endpointUri(String path) {
    return Uri.parse(endpoint).resolve(path);
  }
}

/// Credentials used to connect to the PowerSync dev API.
///
/// Used by [DevConnector].
///
/// These cannot be used for the main PowerSync APIs. [DevConnector] uses these
/// credentials to automatically fetch [PowerSyncCredentials].
class DevCredentials {
  /// Dev endpoint.
  String endpoint;

  /// Dev token.
  String? token;

  /// User id.
  String? userId;

  DevCredentials({required this.endpoint, this.token, this.userId});

  factory DevCredentials.fromJson(Map<String, dynamic> parsed) {
    return DevCredentials(
        endpoint: parsed['endpoint'],
        token: parsed['token'],
        userId: parsed['user_id']);
  }

  factory DevCredentials.fromString(String credentials) {
    var parsed = jsonDecode(credentials);
    return DevCredentials.fromJson(parsed);
  }

  static DevCredentials? fromOptionalString(String? credentials) {
    if (credentials == null) {
      return null;
    }
    return DevCredentials.fromString(credentials);
  }

  Map<String, dynamic> toJson() {
    return {'endpoint': endpoint, 'token': token, 'user_id': userId};
  }
}

/// Connects to the PowerSync service in development mode.
///
/// Development mode has the following functionality:
///   1. Login using static username & password combinations, returning [DevCredentials].
///   2. Refresh PowerSync token using [DevCredentials].
///   3. Write directly to the SQL database using a basic update endpoint.
///
/// By default, credentials are stored in memory only. Subclass and override
/// [DevConnector.storeDevCredentials] and [DevConnector.loadDevCredentials] to use persistent storage.
///
/// Development mode is intended to get up and running quickly, but is not for
/// production use. For production, write a custom connector.
class DevConnector extends PowerSyncBackendConnector {
  PowerSyncCredentials? credentials;

  DevCredentials? _inMemoryDevCredentials;

  /// Store the credentials after login, or when clearing / changing it.
  ///
  /// Default implementation stores in memory - override to use persistent storage.
  Future<void> storeDevCredentials(DevCredentials credentials) async {
    _inMemoryDevCredentials = credentials;
  }

  /// Load the stored credentials.
  ///
  /// Default implementation stores in memory - override to use persistent storage.
  Future<DevCredentials?> loadDevCredentials() async {
    return _inMemoryDevCredentials;
  }

  /// Get the user id associated with the dev credentials.
  Future<String?> getUserId() async {
    final credentials = await loadDevCredentials();
    return credentials?.userId;
  }

  /// Get the dev endpoint associated with the dev credentials.
  Future<String?> getEndpoint() async {
    final credentials = await loadDevCredentials();
    return credentials?.endpoint;
  }

  /// Clear the dev token.
  ///
  /// Use this if the user logged out, or authentication fails.
  Future<void> clearDevToken() async {
    var existing = await loadDevCredentials();
    if (existing != null) {
      existing.token = null;
      storeDevCredentials(existing);
    }
    credentials = null;
  }

  /// Whether a dev token is available.
  Future<bool> hasCredentials() async {
    final devCredentials = await loadDevCredentials();
    return devCredentials?.token != null;
  }

  /// Use the PowerSync dev API to log in.
  Future<void> devLogin(
      {required String endpoint,
      required String user,
      required String password}) async {
    final uri = Uri.parse(endpoint).resolve('dev/auth.json');
    final res = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user': user, 'password': password}));

    if (res.statusCode == 200) {
      var parsed = jsonDecode(res.body);
      storeDevCredentials(DevCredentials(
          endpoint: endpoint,
          token: parsed['data']['token'],
          userId: parsed['data']['user_id']));
    } else {
      throw HttpException(res.reasonPhrase ?? 'Request failed', uri: uri);
    }
  }

  @override
  Future<PowerSyncCredentials?> getCredentials() async {
    if (credentials == null) {
      await refreshCredentials();
    }
    return credentials;
  }

  @override
  Future<void> refreshCredentials() async {
    final devCredentials = await loadDevCredentials();
    if (devCredentials?.token == null) {
      return;
    }
    final uri = Uri.parse(devCredentials!.endpoint).resolve('dev/token.json');
    final res = await http
        .post(uri, headers: {'Authorization': 'Token ${devCredentials.token}'});
    if (res.statusCode == 401) {
      clearDevToken();
    }
    if (res.statusCode != 200) {
      throw HttpException(res.reasonPhrase ?? 'Request failed', uri: uri);
    }

    credentials = PowerSyncCredentials.fromJson(jsonDecode(res.body)['data']);
  }

  /// Upload changes using the PowerSync dev API.
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) {
      return;
    }

    final credentials = await getCredentials();
    if (credentials == null) {
      throw AssertionError("Not logged in");
    }
    final uri = credentials.endpointUri('crud.json');

    final response = await http.post(uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Id': credentials.userId ?? '',
          'Authorization': "Token ${credentials.token}"
        },
        body: jsonEncode({'data': batch.crud}));

    if (response.statusCode == 401) {
      await refreshCredentials();
    }

    if (response.statusCode != 200) {
      throw HttpException(response.reasonPhrase ?? "Authentication failed",
          uri: uri);
    }

    final _ = jsonDecode(response.body);
    await batch.complete();
  }
}

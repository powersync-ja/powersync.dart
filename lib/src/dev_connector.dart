// Connects to the PowerSync service in development mode
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import './powersync_database.dart';

class DevConnector implements PowerSyncBackendConnector {
  final Future<String?> Function() credentialsCallback;

  const DevConnector({required this.credentialsCallback});

  @override
  Future<String?> getCredentials() {
    return credentialsCallback();
  }

  @override
  Future<void> uploadData(PowerSyncDatabase powerSync) async {
    final batch = await powerSync.getCrudBatch();
    if (batch == null) {
      return;
    }

    final credentialsRaw = await getCredentials();
    if (credentialsRaw == null) {
      throw AssertionError("Not logged in");
    }
    final credentials = jsonDecode(credentialsRaw);
    final uri = Uri.parse(credentials['endpoint']).resolve('crud.json');

    final response = await http.post(uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Id': credentials['user_id'],
          'Authorization': "Token ${credentials['token']}"
        },
        body: jsonEncode({'data': batch.crud}));
    if (response.statusCode != 200) {
      throw HttpException(response.reasonPhrase ?? "Request failed", uri: uri);
    }

    final body = jsonDecode(response.body);
    await batch.complete();
  }
}

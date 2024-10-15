import 'package:powersync_core/powersync_core.dart';
import 'package:test/test.dart';

void main() {
  group('PowerSyncCredentials', () {
    test('getExpiryDate', () async {
      // Specifically test a token with a "-" character and missing padding
      final token =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ9Pn0-YWIiLCJpYXQiOjE3MDc3Mzk0MDAsImV4cCI6MTcwNzczOTUwMH0=.IVoAtpJ7jfwLbqlyJGYHPCvljLis_fHj2Qvdqlj8AQU';
      expect(PowerSyncCredentials.getExpiryDate(token)?.toUtc(),
          equals(DateTime.parse('2024-02-12T12:05:00Z')));
    });
  });
}

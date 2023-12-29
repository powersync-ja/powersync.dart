import 'package:powersync/sqlite3.dart' as sqlite;
import '../powersync.dart';

class Profile {
  Profile({
    required this.id,
    required this.username,
    required this.createdAt,
  });

  /// User ID of the profile
  final String id;

  /// Username of the profile
  final String username;

  /// Date and time when the profile was created
  final DateTime createdAt;

  Profile.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        username = map['username'],
        createdAt = DateTime.parse(map['created_at']);

  factory Profile.fromRow(sqlite.Row row) {
    return Profile(
        id: row['id'],
        username: row['username'],
        createdAt: DateTime.parse(row['created_at']));
  }

  static Future<Profile> findProfileById(String id) async {
    final result = await db.get('SELECT * FROM profiles where id = ?', [id]);
    return Profile.fromRow(result);
  }
}

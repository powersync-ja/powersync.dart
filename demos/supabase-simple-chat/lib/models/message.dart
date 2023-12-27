import '../powersync.dart';
import 'package:powersync/sqlite3.dart' as sqlite;

class Message {
  Message({
    required this.id,
    required this.profileId,
    required this.content,
    required this.createdAt,
    required this.isMine,
  });

  /// ID of the message
  final String id;

  /// ID of the user who posted the message
  final String profileId;

  /// Text content of the message
  final String content;

  /// Date and time when the message was created
  final DateTime createdAt;

  /// Whether the message is sent by the user or not.
  final bool isMine;

  Message.fromMap({
    required Map<String, dynamic> map,
    required String myUserId,
  })  : id = map['id'],
        profileId = map['profile_id'],
        content = map['content'],
        createdAt = DateTime.parse(map['created_at']),
        isMine = myUserId == map['profile_id'];

  factory Message.fromRow(sqlite.Row row, String myUserId) {
    return Message(
        id: row['id'],
        profileId: row['profile_id'],
        content: row['content'],
        createdAt: DateTime.parse(row['created_at']),
        isMine: myUserId == row['profile_id']);
  }

  static Stream<List<Message>> watchMessages(String myUserId) {
    return db
        .watch('SELECT * FROM messages ORDER BY created_at DESC')
        .map((results) {
      return results
          .map((row) => Message.fromRow(row, myUserId))
          .toList(growable: false);
    });
  }

  static Future<void> create(String profileId, String content) async {
    await db.execute(
        'INSERT INTO messages(id, created_at, profile_id, content) VALUES(uuid(), datetime(), ?, ?)',
        [profileId, content]);
  }
}

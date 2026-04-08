import 'package:powersync/powersync.dart';
import 'package:test/test.dart';

void main() {
  group('Sync types', () {
    test('stream priority comparisons', () {
      expect(StreamPriority(0) < StreamPriority(3), isFalse);
      expect(StreamPriority(0) > StreamPriority(3), isTrue);
      expect(StreamPriority(0) >= StreamPriority(3), isTrue);
      expect(StreamPriority(0) >= StreamPriority(0), isTrue);
    });
  });
}

abstract class LocalStorage {
  Future<void> save(String id, List<int> bytes, {String? mediaType, Map<String, dynamic>? metadata});
  Future<List<int>?> read(String id);
  Future<void> delete(String id);
  // ... other methods
}

// Example: IO implementation (can be in a separate file, not imported by default)
class IOLocalStorage implements LocalStorage {
  @override
  Future<void> save(String id, List<int> bytes, {String? mediaType, Map<String, dynamic>? metadata}) {
    throw UnimplementedError();
  }

  @override
  Future<List<int>?> read(String id) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}
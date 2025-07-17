class AttachmentContext {
  // Used for transactional/exclusive operations
  Future<T> runExclusive<T>(Future<T> Function() action) async {
    // Implement async mutex/lock here if needed
    return await action();
  }
}
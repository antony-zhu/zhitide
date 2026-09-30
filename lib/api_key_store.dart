import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyStore {
  ApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'deepseek_api_key';
  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String key) =>
      _storage.write(key: _key, value: key.trim());
}

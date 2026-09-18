import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  const SettingsService();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _finnhubKey = 'finnhub_api_key';
  static const _brapiKey = 'brapi_api_key';
  static const _tursoUrlKey = 'turso_database_url';
  static const _tursoTokenKey = 'turso_auth_token';

  Future<String?> loadFinnhubKey() => _storage.read(key: _finnhubKey);

  Future<void> saveFinnhubKey(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      await _storage.delete(key: _finnhubKey);
    } else {
      await _storage.write(key: _finnhubKey, value: clean);
    }
  }

  Future<String?> loadBrapiKey() => _storage.read(key: _brapiKey);

  Future<void> saveBrapiKey(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      await _storage.delete(key: _brapiKey);
    } else {
      await _storage.write(key: _brapiKey, value: clean);
    }
  }

  Future<({String url, String token})?> loadTursoCredentials() async {
    final values = await Future.wait([
      _storage.read(key: _tursoUrlKey),
      _storage.read(key: _tursoTokenKey),
    ]);
    final url = values[0]?.trim() ?? '';
    final token = values[1]?.trim() ?? '';
    if (url.isEmpty || token.isEmpty) return null;
    return (url: url, token: token);
  }

  Future<void> saveTursoCredentials(String url, String token) async {
    await _storage.write(key: _tursoUrlKey, value: url.trim());
    await _storage.write(key: _tursoTokenKey, value: token.trim());
  }

  Future<void> clearTursoCredentials() async {
    await Future.wait([
      _storage.delete(key: _tursoUrlKey),
      _storage.delete(key: _tursoTokenKey),
    ]);
  }
}

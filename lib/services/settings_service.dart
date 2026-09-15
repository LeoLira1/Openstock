import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  const SettingsService();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _finnhubKey = 'finnhub_api_key';

  Future<String?> loadFinnhubKey() => _storage.read(key: _finnhubKey);

  Future<void> saveFinnhubKey(String value) async {
    final clean = value.trim();
    if (clean.isEmpty) {
      await _storage.delete(key: _finnhubKey);
    } else {
      await _storage.write(key: _finnhubKey, value: clean);
    }
  }
}


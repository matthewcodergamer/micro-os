import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class GithubIdentity {
  const GithubIdentity({required this.login, required this.name});

  final String login;
  final String name;

  String get displayName => name.isEmpty ? login : name;
}

/// Stores the GitHub Personal Access Token in the platform keystore and checks
/// it against the GitHub API. The token is never written to shared preferences.
class GithubAuth {
  static const _kToken = 'github.pat';
  static const _kLogin = 'github.login';
  static const _kHfToken = 'huggingface.token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> readToken() async {
    try {
      return await _storage.read(key: _kToken);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readHuggingFaceToken() async {
    try {
      return await _storage.read(key: _kHfToken);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveHuggingFaceToken(String token) async {
    await _storage.write(key: _kHfToken, value: token);
  }

  Future<void> clearHuggingFaceToken() async {
    await _storage.delete(key: _kHfToken);
  }

  Future<String?> verifyHuggingFace(String token) async {
    try {
      final response = await http.get(
        Uri.parse('https://huggingface.co/api/whoami-v2'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['name'] as String?) ?? (body['fullname'] as String?) ?? 'Hugging Face account';
    } catch (_) {
      return null;
    }
  }

  Future<String?> readLogin() async {
    try {
      return await _storage.read(key: _kLogin);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToken(String token, String login) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kLogin, value: login);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kLogin);
  }

  /// Returns the identity for [token], or null when GitHub rejects it.
  Future<GithubIdentity?> verify(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('https://api.github.com/user'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final login = body['login'] as String? ?? '';
      final name = body['name'] as String? ?? '';
      if (login.isEmpty) return null;
      return GithubIdentity(login: login, name: name);
    } catch (_) {
      return null;
    }
  }
}

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class CacheEntry {
  final String body;
  final Map<String, String> headers;
  final DateTime expiresAt;

  CacheEntry({
    required this.body,
    required this.headers,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'body': body,
      'headers': headers,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    };
  }

  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      body: json['body'] as String,
      headers: Map<String, String>.from(json['headers'] as Map),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class Store {
  String? _domain;
  Box<String>? _domainKeys;
  Box<String>? _httpToken;
  Box<String>? _httpCache; // Combined cache storage

  bool _isInitialized = false;

  static final _instance = Store._internal();

  factory Store(String domain) {
    if (_instance._httpCache?.isOpen != true) {
      _instance._init(domain);
    }
    return _instance;
  }

  Store._internal();

  Future<void> _init(String domain) async {
    _domain = domain;
    await Hive.initFlutter();
    _domainKeys = await Hive.openBox<String>('domainKeys');

    String? key = _domainKeys?.get(_domain);

    if (key == null) {
      key = base64UrlEncode(Hive.generateSecureKey());
      _domainKeys?.put(_domain, key);
    }

    _httpToken = await Hive.openBox<String>(
      'httpToken',
      encryptionCipher: HiveAesCipher(base64Url.decode(key)),
    );

    _httpCache = await Hive.openBox<String>('httpCache');

    _isInitialized = true;
  }

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      return !_isInitialized;
    });
  }

  void removeToken(String key) {
    if (_httpToken == null) {
      throw Exception("httpToken is not initialized");
    }
    _httpToken?.delete(key);
  }

  void putToken(String key, String value) {
    if (_httpToken == null) {
      throw Exception("httpToken is not initialized");
    }
    _httpToken?.put(key, value);
  }

  String? getToken(String key) {
    if (_httpToken == null) {
      throw Exception("httpToken is not initialized");
    }
    return _httpToken?.get(key);
  }

  // New cache methods with expiration
  void putCacheEntry(String key, CacheEntry entry) {
    if (_httpCache == null) {
      throw Exception("_httpCache is not initialized");
    }
    _httpCache?.put(key, jsonEncode(entry.toJson()));
  }

  CacheEntry? getCacheEntry(String key) {
    if (_httpCache == null) {
      throw Exception("_httpCache is not initialized");
    }

    final cachedData = _httpCache?.get(key);
    if (cachedData == null) return null;

    try {
      final entry = CacheEntry.fromJson(jsonDecode(cachedData));

      // Check if expired and remove if so
      if (entry.isExpired) {
        _httpCache?.delete(key);
        return null;
      }

      return entry;
    } catch (e) {
      // If parsing fails, remove the corrupted entry
      _httpCache?.delete(key);
      return null;
    }
  }

  void removeCacheEntry(String key) {
    if (_httpCache == null) {
      throw Exception("_httpCache is not initialized");
    }
    _httpCache?.delete(key);
  }

  // Clean up expired entries
  Future<void> cleanExpiredCache() async {
    if (_httpCache == null) return;

    final keysToDelete = <String>[];

    for (final key in _httpCache!.keys) {
      final cachedData = _httpCache!.get(key);
      if (cachedData != null) {
        try {
          final entry = CacheEntry.fromJson(jsonDecode(cachedData));
          if (entry.isExpired) {
            keysToDelete.add(key);
          }
        } catch (e) {
          // Remove corrupted entries
          keysToDelete.add(key);
        }
      }
    }

    for (final key in keysToDelete) {
      _httpCache!.delete(key);
    }
  }

  // Clean up entire cache
  Future<void> clearCache() async {
    if (_httpCache == null) return;
    await _httpCache!.clear();
  }
}

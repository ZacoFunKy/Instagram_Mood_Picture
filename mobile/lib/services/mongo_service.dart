import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

class MongoService {
  static final MongoService _instance = MongoService._internal();
  static MongoService get instance => _instance;

  mongo.Db? _db;
  mongo.Db? _mobileDb; // For overrides
  bool _isConnected = false;
  Completer<void>? _connectionCompleter;

  MongoService._internal();

  /// Returns the main DB instance, waiting for connection if necessary.
  Future<mongo.Db> getOrConnect() async {
    if (_isConnected && _db != null) {
      return _db!;
    }

    // If a connection attempt is already in progress, wait for it.
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      await _connectionCompleter!.future;
      if (_db == null) throw Exception("Database connection failed");
      return _db!;
    }

    // Otherwise, start initialization
    await init();
    if (_db == null) throw Exception("Database connection failed after init");
    return _db!;
  }

  Future<void> init() async {
    if (_isConnected) return;

    // Prevent concurrent connection attempts
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      return _connectionCompleter!.future;
    }

    _connectionCompleter = Completer<void>();

    final String? uri = dotenv.env['MONGO_URI'];
    final String? mobileUri = dotenv.env['MONGO_URI_MOBILE'];

    if (uri == null) {
      debugPrint("❌ MONGO_URI missing");
      _connectionCompleter!.complete();
      return;
    }

    try {
      debugPrint("🔌 Connecting to Main MongoDB...");
      _db = await mongo.Db.create(uri);
      await _db!.open();

      if (mobileUri != null) {
        debugPrint("🔌 Connecting to Mobile MongoDB...");
        _mobileDb = await mongo.Db.create(mobileUri);
        await _mobileDb!.open();
      }

      _isConnected = true;
      debugPrint("✅ MongoDB Connected (Persistent)");
    } catch (e) {
      debugPrint("❌ MongoDB Connection Warning: $e");
      // Don't crash, just log. Retry happens on usage if needed.
    } finally {
      if (!_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete();
      }
    }
  }

  mongo.Db? get db => _db;
  mongo.Db? get mobileDb => _mobileDb;
}

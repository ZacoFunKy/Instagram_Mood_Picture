import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

class DatabaseService {
  // Singleton Pattern
  static final DatabaseService _instance = DatabaseService._internal();
  static DatabaseService get instance => _instance;

  mongo.Db? _db;
  mongo.Db? _mobileDb; // For specific mobile overrides if needed
  bool _isConnected = false;
  Completer<void>? _connectionCompleter;

  DatabaseService._internal();

  /// Constants
  static const String collectionName = "daily_logs";

  /// Ensures connection is established before returning the DB instance.
  /// Throws [Exception] if connection fails.
  Future<mongo.Db> get database async {
    if (_isConnected && _db != null && _db!.isConnected) {
      return _db!;
    }

    // If a connection attempt is in progress, wait for it
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      debugPrint("⏳ Database: Waiting for existing connection attempt...");
      await _connectionCompleter!.future;
      // Re-check after wait
      if (_isConnected && _db != null && _db!.isConnected) {
        return _db!;
      }
    }

    // Otherwise connect (Retry Logic)
    debugPrint("🔄 Database: Retrying connection...");
    await _connect();

    // Final check
    if (_db == null || !_db!.isConnected) {
      throw Exception(
          "Connection Failed. Please check your internet connection.");
    }
    return _db!;
  }

  /// Initialize connection (Lazy Loading)
  Future<void> _connect() async {
    // If already connected, skip
    if (_isConnected && _db != null && _db!.isConnected) return;

    // Avoid concurrent connection attempts
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      return _connectionCompleter!.future;
    }

    _connectionCompleter = Completer<void>();

    final String? uri = dotenv.env['MONGO_URI'];
    final String? mobileUri = dotenv.env['MONGO_URI_MOBILE'];

    if (uri == null) {
      debugPrint("❌ ERROR: MONGO_URI is missing in .env");
      _connectionCompleter!.complete();
      return;
    }

    try {
      debugPrint("🔌 MongoDB: Connecting...");
      _db = await mongo.Db.create(uri);
      await _db!.open();

      if (mobileUri != null) {
        debugPrint("🔌 MongoDB (Mobile): Connecting...");
        _mobileDb = await mongo.Db.create(mobileUri);
        await _mobileDb!.open();
      }

      _isConnected = true;
      debugPrint("✅ MongoDB: Connected Successfully");
    } catch (e) {
      debugPrint("❌ MongoDB Connection Error: $e");
      _isConnected = false;
      _db = null;
      _mobileDb = null;
    } finally {
      if (!_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete();
      }
    }
  }

  /// Explicit initialization call (optional, can be called in main)
  void init() {
    _connect(); // Fire and forget
  }

  /// Helper to get the overrides collection
  Future<mongo.DbCollection> get logsCollection async {
    final db = await database;
    // Use mobileDB if available for overrides, else main DB
    final targetDb = _mobileDb ?? db;
    return targetDb.collection(collectionName);
  }
}

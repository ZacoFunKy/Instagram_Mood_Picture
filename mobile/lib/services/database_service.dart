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

    if (uri.contains("localhost") || uri.contains("127.0.0.1")) {
      debugPrint("⚠️ WARNING: You are using 'localhost' in MongoDB URI.");
      debugPrint("   - On Android Emulator, use '10.0.2.2' instead.");
      debugPrint(
          "   - On Real Device, use your PC's LAN IP (e.g., 192.168.x.x).");
    }

    // Force TLS for Android compatibility involving older/custom CAs
    if (!uri.contains("tls=")) {
      uri += (uri.contains("?") ? "&" : "?") + "tls=true&authSource=admin";
    }

    String connectionUri = uri; // uri is verified non-null above

    // Force TLS for Android compatibility involving older/custom CAs
    if (!connectionUri.contains("tls=")) {
      connectionUri += (connectionUri.contains("?") ? "&" : "?") +
          "tls=true&authSource=admin";
    }

    // Fix for Mobile Override URI too
    String? mobileConnectionUri = mobileUri;
    if (mobileConnectionUri != null && !mobileConnectionUri.contains("tls=")) {
      mobileConnectionUri += (mobileConnectionUri.contains("?") ? "&" : "?") +
          "tls=true&authSource=admin";
    }

    try {
      debugPrint("🔌 MongoDB: Connecting to $connectionUri");
      _db = await mongo.Db.create(connectionUri);
      // Increased timeout to 10s to allow for slower networks
      await _db!.open().timeout(const Duration(seconds: 10));

      if (mobileConnectionUri != null) {
        debugPrint("🔌 MongoDB (Mobile): Connecting...");
        _mobileDb = await mongo.Db.create(mobileConnectionUri);
        await _mobileDb!.open().timeout(const Duration(seconds: 10));
      }

      _isConnected = true;
      debugPrint("✅ MongoDB: Connected Successfully");
    } catch (e) {
      debugPrint("❌ MongoDB Connection Error: $e");
      _isConnected = false;
      _db = null;
      _mobileDb = null;
      rethrow; // Explicitly fail so caller catches it
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

  /// Collection: daily_logs (Read-Only validation / History / Stats)
  /// Lives in 'profile_predictor' DB (Main)
  Future<mongo.DbCollection> get dailyLogs async {
    final db = await database;
    return db.collection("daily_logs");
  }

  /// Collection: overrides (Write / Sync)
  /// Lives in 'mobile' DB (Mobile) - Falls back to Main if mobileDB not set
  Future<mongo.DbCollection> get overrides async {
    if (_mobileDb != null && _mobileDb!.isConnected) {
      return _mobileDb!.collection("overrides");
    }
    // Fallback or Error? User said "Sync goes into override".
    // If we only have one DB connected, we might want to check its name,
    // but assuming overrides exists there too or we fail cleanly.
    final db = await database;
    return db.collection("overrides");
  }
}

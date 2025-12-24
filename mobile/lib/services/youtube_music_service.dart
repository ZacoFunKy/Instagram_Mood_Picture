import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to detect currently playing music from YouTube Music (or any media app)
/// Uses Android MediaSession to read metadata of currently playing track
class YouTubeMusicService {
  static const MethodChannel _channel =
      MethodChannel('com.moodpredictor/media_session');

  static final YouTubeMusicService _instance = YouTubeMusicService._internal();
  factory YouTubeMusicService() => _instance;
  YouTubeMusicService._internal() {
    _loadHistory();
  }

  // Local History Cache (Simulating Backend History)
  List<Map<String, dynamic>> _recentTracks = [];
  static const int _historyLimit = 50;

  /// Get currently playing track information
  /// Returns null if no track is playing or if permission denied
  Future<Map<String, dynamic>?> getCurrentTrack() async {
    try {
      final result = await _channel.invokeMethod('getCurrentMediaMetadata');

      if (result == null) return null;

      final track = {
        'title': result['title'] ?? '',
        'artist': result['artist'] ?? '',
        'album': result['album'] ?? '',
        'package': result['package'] ?? '',
      };

      _addToHistory(track);
      return track;
    } catch (e) {
      debugPrint('⚠️ YouTubeMusicService error: $e');
      return null;
    }
  }

  /// Check if YouTube Music (or any media app) is currently playing
  Future<bool> isPlaying() async {
    try {
      final result = await _channel.invokeMethod('isMediaPlaying');
      return result ?? false;
    } catch (e) {
      debugPrint('⚠️ YouTubeMusicService isPlaying error: $e');
      return false;
    }
  }

  /// Stream of track changes (when user changes song)
  Stream<Map<String, dynamic>?> get trackStream {
    return EventChannel('com.moodpredictor/media_session_events')
        .receiveBroadcastStream()
        .map((event) {
      if (event == null) return null;
      final track = {
        'title': event['title'] ?? '',
        'artist': event['artist'] ?? '',
        'album': event['album'] ?? '',
        'package': event['package'] ?? '',
      };
      _addToHistory(track);
      return track;
    });
  }

  // === HISTORY MANAGEMENT ===

  List<Map<String, dynamic>> getRecentTracks() {
    return List.from(_recentTracks);
  }

  Future<void> _addToHistory(Map<String, dynamic> track) async {
    final title = track['title'];
    final artist = track['artist'];

    // Validate inputs
    if (title.isEmpty || artist.isEmpty) return;

    // Check if it's the same as the last track to avoid duplicates (spamming)
    if (_recentTracks.isNotEmpty) {
      final last = _recentTracks.first;
      if (last['title'] == title && last['artist'] == artist) {
        return; // Duplicate
      }
    }

    _recentTracks.insert(0, {
      ...track,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (_recentTracks.length > _historyLimit) {
      _recentTracks = _recentTracks.sublist(0, _historyLimit);
    }

    _saveHistory();
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('music_history_cache', json.encode(_recentTracks));
    } catch (e) {
      debugPrint("Error saving music history: $e");
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('music_history_cache');
      if (jsonStr != null) {
        final List<dynamic> list = json.decode(jsonStr);
        _recentTracks = list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Error loading music history: $e");
    }
  }
}

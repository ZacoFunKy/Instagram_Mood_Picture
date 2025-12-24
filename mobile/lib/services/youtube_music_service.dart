import 'package:flutter/services.dart';
import 'dart:async';

/// Service to detect currently playing music from YouTube Music (or any media app)
/// Uses Android MediaSession to read metadata of currently playing track
class YouTubeMusicService {
  static const MethodChannel _channel = MethodChannel('com.moodpredictor/media_session');
  
  static final YouTubeMusicService _instance = YouTubeMusicService._internal();
  factory YouTubeMusicService() => _instance;
  YouTubeMusicService._internal();

  /// Get currently playing track information
  /// Returns null if no track is playing or if permission denied
  Future<Map<String, dynamic>?> getCurrentTrack() async {
    try {
      final result = await _channel.invokeMethod('getCurrentMediaMetadata');
      
      if (result == null) return null;
      
      return {
        'title': result['title'] ?? '',
        'artist': result['artist'] ?? '',
        'album': result['album'] ?? '',
        'package': result['package'] ?? '', // e.g. "com.google.android.apps.youtube.music"
      };
    } catch (e) {
      print('⚠️ YouTubeMusicService error: $e');
      return null;
    }
  }

  /// Check if YouTube Music (or any media app) is currently playing
  Future<bool> isPlaying() async {
    try {
      final result = await _channel.invokeMethod('isMediaPlaying');
      return result ?? false;
    } catch (e) {
      print('⚠️ YouTubeMusicService isPlaying error: $e');
      return false;
    }
  }

  /// Stream of track changes (when user changes song)
  Stream<Map<String, dynamic>?> get trackStream {
    return EventChannel('com.moodpredictor/media_session_events')
        .receiveBroadcastStream()
        .map((event) {
      if (event == null) return null;
      return {
        'title': event['title'] ?? '',
        'artist': event['artist'] ?? '',
        'album': event['album'] ?? '',
        'package': event['package'] ?? '',
      };
    });
  }
}

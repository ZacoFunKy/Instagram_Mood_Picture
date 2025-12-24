import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Replicates backend 'yt_music.py' logic:
/// Fetches listening history directly from YouTube Music Cloud using cookies.
class YoutubeMusicCloudService {
  static final YoutubeMusicCloudService _instance =
      YoutubeMusicCloudService._internal();
  factory YoutubeMusicCloudService() => _instance;
  YoutubeMusicCloudService._internal();

  static const String _kCacheKey = 'yt_cloud_cache_data';
  static const String _kTimeKey = 'yt_cloud_cache_time';
  static const int _kCacheDurationMinutes = 15;

  /// Fetches recent tracks from Cloud History
  /// Uses caching to prevent spamming the API.
  Future<List<Map<String, dynamic>>> getRecentTracks(
      {bool forceRefresh = false}) async {
    final logger = AppLogger();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Check Cache
      if (!forceRefresh) {
        final lastTimeStr = prefs.getString(_kTimeKey);
        if (lastTimeStr != null) {
          final lastTime = DateTime.parse(lastTimeStr);
          final diff = DateTime.now().difference(lastTime).inMinutes;

          if (diff < _kCacheDurationMinutes) {
            final cachedData = prefs.getString(_kCacheKey);
            if (cachedData != null) {
              logger.log("Using Cached Cloud Music ($diff mins old)");
              final List<dynamic> jsonList = json.decode(cachedData);
              return jsonList.cast<Map<String, dynamic>>();
            }
          }
        }
      }

      logger.log("Fetching fresh Cloud Music history...");

      // 2. Load Headers
      final authData = await rootBundle.loadString('assets/browser_auth.json');
      final headers = Map<String, String>.from(json.decode(authData));

      // 3. Extract API Key
      final homeResp =
          await http.get(Uri.parse("https://music.youtube.com"), headers: {
        'User-Agent': headers['user-agent'] ?? '',
        'Cookie': headers['cookie'] ?? '',
      });

      final apiKeyMatch =
          RegExp(r'"INNERTUBE_API_KEY":"(.*?)"').firstMatch(homeResp.body);
      if (apiKeyMatch == null) {
        logger.error("Could not scrape YTM API Key");
        return [];
      }
      final apiKey = apiKeyMatch.group(1);

      // 4. Execute JSON Request
      final contextPayload = {
        "context": {
          "client": {
            "clientName": "WEB_REMIX",
            "clientVersion": "1.20230816.01.00",
            "hl": "en"
          },
          "user": {"lockedSafetyMode": false}
        },
        "browseId": "FEmusic_history"
      };

      final response = await http.post(
          Uri.parse("https://music.youtube.com/youtubei/v1/browse?key=$apiKey"),
          headers: headers,
          body: json.encode(contextPayload));

      if (response.statusCode != 200) {
        logger.error("YTM API Error: ${response.statusCode}");
        return [];
      }

      // 5. Parse
      final data = json.decode(response.body);
      final tracks = <Map<String, dynamic>>[];

      try {
        // Safe traversal (simplified/robust)
        // Try structure: contents -> singleColumnBrowseResultsRenderer...
        // If structure changes, this might fail, so we catch it.
        final tabs = data['contents']['singleColumnBrowseResultsRenderer']
            ['tabs'] as List;
        final tabContent = tabs[0]['tabRenderer']['content'];
        final sections = tabContent['sectionListRenderer']['contents'] as List;

        for (var section in sections) {
          if (section.containsKey('musicShelfRenderer')) {
            final items = section['musicShelfRenderer']['contents'] as List;
            for (var item in items) {
              final renderer = item['musicResponsiveListItemRenderer'];
              if (renderer != null) {
                final title = _getText(renderer['flexColumns'][0]
                    ['musicResponsiveListItemFlexColumnRenderer']['text']);
                final artist = _getText(renderer['flexColumns'][1]
                    ['musicResponsiveListItemFlexColumnRenderer']['text']);

                tracks
                    .add({'title': title, 'artist': artist, 'source': 'Cloud'});
              }
            }
          }
        }
      } catch (e) {
        logger.error("Error parsing YTM response structure", e);
      }

      logger.log("✅ Fetched ${tracks.length} tracks from YTM Cloud");

      // 6. Save Cache
      if (tracks.isNotEmpty) {
        await prefs.setString(_kCacheKey, json.encode(tracks));
        await prefs.setString(_kTimeKey, DateTime.now().toIso8601String());
      }

      return tracks;
    } catch (e, stack) {
      logger.error("Critical Error fetching Cloud Music", e, stack);
      return [];
    }
  }

  String _getText(dynamic textObj) {
    if (textObj == null || textObj['runs'] == null) return "Unknown";
    return (textObj['runs'] as List).map((r) => r['text']).join("");
  }
}

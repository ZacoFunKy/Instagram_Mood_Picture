import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service to enrich YouTube Music tracks with Spotify audio features
/// Mirrors the backend enrichment logic from spotify.py
class SpotifyEnrichmentService {
  static const String _authUrl = 'https://accounts.spotify.com/api/token';
  static const String _searchUrl = 'https://api.spotify.com/v1/search';
  static const String _trackUrl = 'https://api.spotify.com/v1/tracks';
  
  static final SpotifyEnrichmentService _instance = SpotifyEnrichmentService._internal();
  factory SpotifyEnrichmentService() => _instance;
  SpotifyEnrichmentService._internal();

  String? _accessToken;
  DateTime? _tokenExpiry;

  /// Get access token using Client Credentials flow
  Future<void> _authenticate() async {
    final clientId = dotenv.env['SPOTIFY_CLIENT_ID'];
    final clientSecret = dotenv.env['SPOTIFY_CLIENT_SECRET'];

    if (clientId == null || clientSecret == null) {
      throw Exception('Spotify credentials missing in .env');
    }

    final credentials = base64.encode(utf8.encode('$clientId:$clientSecret'));

    try {
      final response = await http.post(
        Uri.parse(_authUrl),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));
        print('✅ Spotify authenticated');
      } else {
        throw Exception('Spotify auth failed: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Spotify auth error: $e');
      rethrow;
    }
  }

  /// Ensure we have a valid token
  Future<void> _ensureAuthenticated() async {
    if (_accessToken == null || 
        _tokenExpiry == null || 
        DateTime.now().isAfter(_tokenExpiry!)) {
      await _authenticate();
    }
  }

  /// Search for a track on Spotify
  Future<String?> _searchTrack(String title, String artist) async {
    await _ensureAuthenticated();

    final query = Uri.encodeComponent('track:$title artist:$artist');
    final url = '$_searchUrl?q=$query&type=track&limit=1';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks']?['items'] as List?;
        if (tracks != null && tracks.isNotEmpty) {
          return tracks[0]['id'] as String?;
        }
      }
    } catch (e) {
      print('⚠️ Spotify search error: $e');
    }
    return null;
  }

  /// Get track details and estimate audio features
  Future<Map<String, dynamic>> _getTrackFeatures(String trackId) async {
    await _ensureAuthenticated();

    try {
      final response = await http.get(
        Uri.parse('$_trackUrl/$trackId'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _estimateFeatures(data);
      }
    } catch (e) {
      print('⚠️ Spotify track fetch error: $e');
    }
    return _defaultFeatures();
  }

  /// Estimate audio features from track metadata (like backend does)
  Map<String, dynamic> _estimateFeatures(Map<String, dynamic> trackData) {
    final popularity = (trackData['popularity'] ?? 50) / 100.0;
    final isExplicit = trackData['explicit'] ?? false;

    // Energy: popularity + explicit bonus
    double energy = popularity * 0.8;
    if (isExplicit) energy = (energy + 0.2).clamp(0.0, 1.0);

    // Valence: popularity-based with floor
    double valence = (popularity * 0.7 + 0.15).clamp(0.0, 1.0);

    // Danceability: similar to energy
    double danceability = (energy * 0.9).clamp(0.0, 1.0);

    // Tempo: estimated range 100-160 BPM
    int tempo = (100 + (energy * 60)).round();

    return {
      'valence': valence,
      'energy': energy,
      'danceability': danceability,
      'tempo': tempo,
    };
  }

  /// Default features when enrichment fails
  Map<String, dynamic> _defaultFeatures() {
    return {
      'valence': 0.5,
      'energy': 0.5,
      'danceability': 0.5,
      'tempo': 120,
    };
  }

  /// Public API: Enrich a track with Spotify features
  /// Mirrors yt_music.py enrichment logic
  Future<Map<String, dynamic>> enrichTrack(String title, String artist) async {
    if (title.isEmpty || artist.isEmpty) {
      return _defaultFeatures();
    }

    try {
      final trackId = await _searchTrack(title, artist);
      if (trackId != null) {
        return await _getTrackFeatures(trackId);
      }
    } catch (e) {
      print('⚠️ Spotify enrichment failed: $e');
    }

    return _defaultFeatures();
  }

  /// Check if Spotify is available (credentials present)
  bool isAvailable() {
    return dotenv.env['SPOTIFY_CLIENT_ID'] != null && 
           dotenv.env['SPOTIFY_CLIENT_SECRET'] != null;
  }
}

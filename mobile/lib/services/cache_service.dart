import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Smart caching service to avoid repeated API calls
/// Caches weather, location, backend predictions with TTL
class CacheService {
  static const Duration _weatherTTL = Duration(hours: 2);
  static const Duration _backendTTL = Duration(hours: 6);
  static const Duration _locationTTL = Duration(days: 1);

  /// Check if weather cache is valid (< 2h old)
  static Future<bool> isWeatherCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString('weather_cache_timestamp');
    if (timestamp == null) return false;
    
    final cacheTime = DateTime.parse(timestamp);
    return DateTime.now().difference(cacheTime) < _weatherTTL;
  }

  /// Get cached weather data
  static Future<Map<String, String>?> getCachedWeather() async {
    if (!await isWeatherCacheValid()) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final temp = prefs.getString('cached_temp');
    final emoji = prefs.getString('cached_weather_emoji');
    final city = prefs.getString('cached_city');
    
    if (temp == null || emoji == null) return null;
    
    return {
      'temperature': temp,
      'emoji': emoji,
      'city': city ?? '',
    };
  }

  /// Cache weather data
  static Future<void> cacheWeather({
    required String temperature,
    required String emoji,
    required String city,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('cached_temp', temperature),
      prefs.setString('cached_weather_emoji', emoji),
      prefs.setString('cached_city', city),
      prefs.setString('weather_cache_timestamp', DateTime.now().toIso8601String()),
    ]);
  }

  /// Check if backend prediction cache is valid (< 6h old)
  static Future<bool> isBackendCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString('backend_cache_timestamp');
    if (timestamp == null) return false;
    
    final cacheTime = DateTime.parse(timestamp);
    return DateTime.now().difference(cacheTime) < _backendTTL;
  }

  /// Get cached backend prediction
  static Future<Map<String, dynamic>?> getCachedBackendPrediction() async {
    if (!await isBackendCacheValid()) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final dataJson = prefs.getString('backend_prediction_data');
    if (dataJson == null) return null;
    
    try {
      return json.decode(dataJson) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Cache backend prediction data
  static Future<void> cacheBackendPrediction(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('backend_prediction_data', json.encode(data)),
      prefs.setString('backend_cache_timestamp', DateTime.now().toIso8601String()),
    ]);
  }

  /// Check if location cache is valid (< 1 day old)
  static Future<bool> isLocationCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString('location_cache_timestamp');
    if (timestamp == null) return false;
    
    final cacheTime = DateTime.parse(timestamp);
    return DateTime.now().difference(cacheTime) < _locationTTL;
  }

  /// Get cached location
  static Future<Map<String, double>?> getCachedLocation() async {
    if (!await isLocationCacheValid()) return null;
    
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('cached_latitude');
    final lng = prefs.getDouble('cached_longitude');
    
    if (lat == null || lng == null) return null;
    
    return {
      'latitude': lat,
      'longitude': lng,
    };
  }

  /// Cache location coordinates
  static Future<void> cacheLocation({
    required double latitude,
    required double longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble('cached_latitude', latitude),
      prefs.setDouble('cached_longitude', longitude),
      prefs.setString('location_cache_timestamp', DateTime.now().toIso8601String()),
    ]);
  }

  /// Clear all caches
  static Future<void> clearAllCaches() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('weather_cache_timestamp'),
      prefs.remove('backend_cache_timestamp'),
      prefs.remove('location_cache_timestamp'),
      prefs.remove('backend_prediction_data'),
    ]);
  }

  /// Get cache statistics for debugging
  static Future<Map<String, String>> getCacheStats() async {
    final prefs = await SharedPreferences.getInstance();
    
    final weatherValid = await isWeatherCacheValid();
    final backendValid = await isBackendCacheValid();
    final locationValid = await isLocationCacheValid();
    
    return {
      'weather': weatherValid ? '✅ Valid' : '❌ Expired',
      'backend': backendValid ? '✅ Valid' : '❌ Expired',
      'location': locationValid ? '✅ Valid' : '❌ Expired',
    };
  }
}

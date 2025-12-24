import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';

/// Google Calendar Service using Service Account (same as backend)
/// Uses GOOGLE_SERVICE_ACCOUNT env variable for authentication
/// No user login required - uses service account credentials
class GoogleCalendarService {
  calendar.CalendarApi? _calendarApi;
  DateTime? _lastAuth;
  
  /// Authenticate using Service Account (no user login required)
  Future<void> _authenticate() async {
    // Re-authenticate every 50 minutes (tokens expire after 1h)
    if (_calendarApi != null && _lastAuth != null) {
      final age = DateTime.now().difference(_lastAuth!);
      if (age.inMinutes < 50) {
        return; // Token still valid
      }
    }
    
    final serviceAccountJson = dotenv.env['GOOGLE_SERVICE_ACCOUNT'];
    if (serviceAccountJson == null || serviceAccountJson.isEmpty) {
      throw Exception('GOOGLE_SERVICE_ACCOUNT not configured in .env');
    }
    
    final accountCredentials = ServiceAccountCredentials.fromJson(
      json.decode(serviceAccountJson),
    );
    
    final scopes = [calendar.CalendarApi.calendarReadonlyScope];
    
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    _calendarApi = calendar.CalendarApi(client);
    _lastAuth = DateTime.now();
  }
  
  /// Fetch today's events from all configured calendars
  /// Returns list in same format as backend for compatibility
  Future<List<Map<String, dynamic>>> getTodayEvents() async {
    try {
      await _authenticate();
      
      final calendarIdsStr = dotenv.env['TARGET_CALENDAR_ID'];
      if (calendarIdsStr == null || calendarIdsStr.isEmpty) {
        print('⚠️ TARGET_CALENDAR_ID not configured');
        return [];
      }
      
      final calendarIds = calendarIdsStr.split(',').map((e) => e.trim()).toList();
      
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      final allEvents = <Map<String, dynamic>>[];
      
      for (final calendarId in calendarIds) {
        try {
          final events = await _calendarApi!.events.list(
            calendarId,
            timeMin: startOfDay.toUtc(),
            timeMax: endOfDay.toUtc(),
            singleEvents: true,
            orderBy: 'startTime',
          );
          
          for (final event in events.items ?? []) {
            allEvents.add({
              'summary': event.summary ?? 'Busy',
              'start': {
                'dateTime': event.start?.dateTime?.toIso8601String() ?? 
                            event.start?.date?.toIso8601String() ?? 
                            DateTime.now().toIso8601String(),
              },
              'description': event.description,
              'location': event.location,
              'calendar_name': calendarId,
            });
          }
          
          print('📅 Fetched ${events.items?.length ?? 0} events from $calendarId');
        } catch (e) {
          print('⚠️ Failed to fetch calendar $calendarId: $e');
        }
      }
      
      print('✅ Total events today: ${allEvents.length}');
      return allEvents;
    } catch (e) {
      print('⚠️ Calendar fetch error: $e');
      return [];
    }
  }
}

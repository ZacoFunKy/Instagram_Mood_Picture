import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis_auth/auth_io.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Service for direct Google Calendar API access
/// Replaces backend calendar fetching with real-time event access
class GoogleCalendarService {
  static final GoogleCalendarService _instance =
      GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [cal.CalendarApi.calendarReadonlyScope],
  );

  GoogleSignInAccount? _currentUser;
  cal.CalendarApi? _calendarApi;

  /// Initialize and sign in silently (for app startup)
  Future<bool> signInSilently() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser == null) {
        // Not signed in previously
        return false;
      }
      return await _authenticate();
    } catch (e) {
      print('⚠️ Google Calendar silent sign-in error: $e');
      return false;
    }
  }

  /// Interactive Sign In (User clicks button)
  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) return false;
      return await _authenticate();
    } catch (e) {
      print('⚠️ Google Calendar sign-in error: $e');
      return false;
    }
  }

  Future<bool> _authenticate() async {
    try {
      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _calendarApi = cal.CalendarApi(authenticateClient);
      print('✅ Google Calendar connected for ${_currentUser!.email}');
      return true;
    } catch (e) {
      print('⚠️ Auth headers error: $e');
      return false;
    }
  }

  /// Check if user is signed in
  bool get isSignedIn => _currentUser != null && _calendarApi != null;

  /// Get today's events
  Future<List<Map<String, dynamic>>> getTodayEvents() async {
    if (!isSignedIn) {
      print('⚠️ Not signed in to Google Calendar');
      return [];
    }

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final events = await _calendarApi!.events.list(
        'primary',
        timeMin: startOfDay.toUtc(),
        timeMax: endOfDay.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (events.items == null || events.items!.isEmpty) {
        print('📅 No events today');
        return [];
      }

      final result = events.items!.map((event) {
        final start = event.start?.dateTime ?? event.start?.date;
        return {
          'summary': event.summary ?? 'No title',
          'start': {
            'dateTime':
                start?.toIso8601String() ?? DateTime.now().toIso8601String(),
          },
          'description': event.description ?? '',
          'location': event.location ?? '',
        };
      }).toList();

      print('✅ Loaded ${result.length} events from Google Calendar');
      return result;
    } catch (e) {
      print('⚠️ Google Calendar fetch error: $e');
      return [];
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _calendarApi = null;
  }
}

/// HTTP client for Google API auth
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

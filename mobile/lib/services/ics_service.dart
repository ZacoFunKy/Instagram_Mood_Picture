import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:icalendar_parser/icalendar_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class IcsService {
  static final IcsService _instance = IcsService._internal();
  factory IcsService() => _instance;
  IcsService._internal();

  // Hardcoded URLs since we can't easily read ics_config.json from assets without loading it,
  // or we can load it from assets if we add it to pubspec.
  // For now, I'll put the URLs here for simplicity as requested,
  // or I can try to load the config file if I add it to assets.
  // The user has 'ics_config.json' in root. I will assume I can't access root file easily
  // without adding to assets. Let's hardcode them for now to ensure it works "like backend".
  final List<String> _icsUrls = [
    "https://apogee.u-bordeaux.fr/planning4/Telechargements/ical/Edt_Taconet.ics?version=2022.0.4.0&idICal=085788E16987A91CFD459F63A68BAB34&param=643d5b312e2e36325d2666683d3126663d31",
    "https://celcat-calendar.vercel.app/api/calendar.ics?token=d71266576b62eebe28751065aec62c4bcd458045a2c17ff1f14053e10cdb8eef"
  ];

  Future<List<Map<String, dynamic>>> getTodayEvents() async {
    List<Map<String, dynamic>> allEvents = [];

    for (String url in _icsUrls) {
      try {
        final events = await _fetchAndParseIcs(url);
        allEvents.addAll(events);
      } catch (e) {
        debugPrint("⚠️ Failed to fetch ICS from $url: $e");
      }
    }
    return allEvents;
  }

  Future<List<Map<String, dynamic>>> _fetchAndParseIcs(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load ICS');
    }

    // Parse ICS
    final iCalendar = ICalendar.fromString(utf8.decode(response.bodyBytes));
    final List<Map<String, dynamic>> todayEvents = [];
    final now = DateTime.now();
    final todayStr = DateFormat('yyyyMMdd').format(now);

    if (iCalendar.data != null) {
      for (var item in iCalendar.data!) {
        if (item['type'] == 'VEVENT') {
          final dtStart = item['dtstart'];
          String? datePart;

          // Handle ICalendarDate (Map) or String
          if (dtStart is Map) {
            datePart = dtStart['dt']; // usually yyyyMMdd or iso
          } else if (dtStart is String) {
            datePart = dtStart.split('T')[0];
          }

          if (datePart != null &&
              datePart.replaceAll('-', '').startsWith(todayStr)) {
            todayEvents.add({
              'summary': item['summary'] ?? 'Busy',
              'start': {
                'dateTime': _parseDate(dtStart),
              },
              'location': item['location'] ?? '',
              'description': item['description'] ?? '',
              'source': 'ICS'
            });
          }
        }
      }
    }

    return todayEvents;
  }

  String _parseDate(dynamic dtStart) {
    // Return ISO string
    if (dtStart is Map) return dtStart['dt'].toString();
    return dtStart.toString();
  }
}

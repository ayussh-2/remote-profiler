import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/log_entry.dart';

class ApiService {
  static const String _baseUrlKey = 'api_base_url';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // Use localhost fallback if not set.
    return prefs.getString(_baseUrlKey) ?? 'http://10.0.2.2:5000/api';
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  static Future<List<LogEntry>> fetchLogs() async {
    final baseUrl = await getBaseUrl();
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/logs'))
          .timeout(const Duration(seconds: 120));
      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        if (data['data'] != null) {
          return (data['data'] as List)
              .map((e) => LogEntry.fromJson(e))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>> detect(
    File image,
    double depthMm,
    double lat,
    double lng,
  ) async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/detect');

    final req = http.MultipartRequest('POST', uri);
    req.fields['depth_mm'] = depthMm.toString();
    req.fields['lat'] = lat.toString();
    req.fields['lng'] = lng.toString();
    req.files.add(await http.MultipartFile.fromPath('image', image.path));

    final streamedRes = await req.send().timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamedRes);

    final data = jsonDecode(res.body);
    if (res.statusCode != 200 || data['error'] != null) {
      throw Exception(data['error'] ?? 'Detection failed');
    }
    return data;
  }
}

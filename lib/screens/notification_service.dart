import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static const String _appId = "6eed93c0-d444-4990-9c6d-cc151a557578";
  static const String _apiKey = "os_v2_app_n3wzhqguirezbhdnzqkruvlvpduhirdpcgwewkujkw4aivmmq2u3zs26a6a2zfkcd7wbb3fnmvrvjggksvewxlwuzoypncwwefv3xyy";
  static const String _oneSignalApi = "https://onesignal.com/api/v1/notifications";

  // ✅ List of CORS proxies (fallback order)
  static const List<String> _corsProxies = [
    "https://corsproxy.io/",
    "https://api.allorigins.win/raw?url=",
    "https://cors-anywhere.herokuapp.com/",
  ];

  static String get _apiUrl => kIsWeb ? "${_corsProxies[0]}$_oneSignalApi" : _oneSignalApi;

  static Future<http.Response?> _postNotification(Map<String, dynamic> payload, {int retryCount = 0}) async {
    if (kIsWeb && retryCount >= _corsProxies.length) {
      print("❌ All CORS proxies exhausted. Notification failed.");
      return null;
    }

    final String url = kIsWeb ? "${_corsProxies[retryCount]}$_oneSignalApi" : _oneSignalApi;
    print("📤 Sending to OneSignal (web: $kIsWeb, proxy: ${kIsWeb ? _corsProxies[retryCount] : 'direct'})");

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $_apiKey',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        print("✅ Notification sent successfully");
        return response;
      } else {
        print("❌ OneSignal error (${response.statusCode}): ${response.body}");
        // If on web and the proxy fails, try the next proxy
        if (kIsWeb && retryCount < _corsProxies.length - 1) {
          print("⚠️ Retrying with next proxy...");
          return await _postNotification(payload, retryCount: retryCount + 1);
        }
        return null;
      }
    } catch (e) {
      print("❌ Network error: $e");
      if (kIsWeb && retryCount < _corsProxies.length - 1) {
        print("⚠️ Retrying with next proxy...");
        return await _postNotification(payload, retryCount: retryCount + 1);
      }
      return null;
    }
  }

  static Future<void> sendToAllUsers({
    required String title,
    required String message,
    Map<String, String>? data,
  }) async {
    await _postNotification({
      'app_id': _appId,
      'headings': {'en': title},
      'contents': {'en': message},
      'included_segments': ['All'],
      'data': data ?? {},
    });
  }

  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String message,
    Map<String, String>? data,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final onesignalId = doc.data()?['onesignalId'];
      if (onesignalId == null || onesignalId.toString().isEmpty) {
        print("⚠️ No OneSignal ID for user $userId");
        return;
      }
      await _postNotification({
        'app_id': _appId,
        'headings': {'en': title},
        'contents': {'en': message},
        'include_player_ids': [onesignalId],
        'data': data ?? {},
      });
    } catch (e) {
      print("❌ sendToUser error: $e");
    }
  }

  static Future<void> sendToRole({
    required String role,
    required String title,
    required String message,
    Map<String, String>? data,
  }) async {
    await _postNotification({
      'app_id': _appId,
      'headings': {'en': title},
      'contents': {'en': message},
      'filters': [
        {"field": "tag", "key": "role", "relation": "=", "value": role}
      ],
      'data': data ?? {},
    });
  }
}
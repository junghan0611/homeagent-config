import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 디바이스 상태 모델 — Go DeviceState와 1:1 매핑
class Device {
  final int nodeId;
  final String name;
  final String room;
  final String type;
  final bool available;
  final Map<String, dynamic> state;

  Device({
    required this.nodeId,
    required this.name,
    this.room = '',
    this.type = '',
    this.available = false,
    this.state = const {},
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      nodeId: json['node_id'] ?? 0,
      name: json['name'] ?? 'Unknown',
      room: json['room'] ?? '',
      type: json['type'] ?? '',
      available: json['available'] ?? false,
      state: Map<String, dynamic>.from(json['state'] ?? {}),
    );
  }

  bool get isOn => state['on'] == true;
  bool get contactOpen => state['contact'] == true;
  int get level => (state['level'] as num?)?.toInt() ?? 0;
  int get colorTemp => (state['color_temp'] as num?)?.toInt() ?? 0;

  bool get isContactSensor => type == 'contact_sensor';
  bool get isTemperatureSensor => type == 'temperature_sensor';
  bool get isDimmable => type == 'dimmable_light' || type == 'color_temp_light';
  bool get isColorTemp => type == 'color_temp_light';
  bool get isSensor => isContactSensor || isTemperatureSensor;
}

/// SSE 이벤트 — Go Event 구조체와 매핑
class SseEvent {
  final String type;
  final int deviceId;
  final String key;
  final dynamic value;

  SseEvent({
    required this.type,
    this.deviceId = 0,
    this.key = '',
    this.value,
  });

  factory SseEvent.fromJson(Map<String, dynamic> json) {
    return SseEvent(
      type: json['type'] ?? '',
      deviceId: json['device_id'] ?? 0,
      key: json['key'] ?? '',
      value: json['value'],
    );
  }
}

/// Go HomeAgent REST API + SSE 클라이언트
/// dart:io HttpClient만 사용 (외부 패키지 없음)
class ApiClient {
  final String baseUrl;

  ApiClient({required this.baseUrl});

  // ─── REST API ───

  Future<List<Device>> getDevices() async {
    final data = await _get('/api/devices');
    if (data is List) {
      return data
          .map((d) => Device.fromJson(Map<String, dynamic>.from(d)))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>?> getHome() async {
    try {
      final data = await _get('/api/home');
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return null;
  }

  Future<bool> healthCheck() async {
    try {
      final data = await _get('/healthz');
      return data is Map && data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<void> sendCommand(
    int nodeId,
    String command, {
    dynamic value,
  }) async {
    final body = <String, dynamic>{
      'node_id': nodeId,
      'command': command,
    };
    if (value != null) body['value'] = value;
    await _post('/api/devices/command', body);
  }

  Future<void> deleteDevice(int nodeId) async {
    await _delete('/api/devices/$nodeId');
  }

  // ─── SSE ───

  /// GET /api/events → text/event-stream
  /// 첫 메시지는 snapshot (전체 디바이스 목록)
  /// 이후 device_state, device_added, device_removed 등
  Stream<SseEvent> eventStream() {
    late StreamController<SseEvent> controller;
    HttpClient? client;
    bool cancelled = false;

    controller = StreamController<SseEvent>(
      onCancel: () {
        cancelled = true;
        client?.close(force: true);
      },
    );

    () async {
      while (!cancelled) {
        try {
          client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5);
          final request =
              await client!.getUrl(Uri.parse('$baseUrl/api/events'));
          final response = await request.close();

          String buffer = '';
          await for (final chunk in response.transform(utf8.decoder)) {
            if (cancelled) break;
            buffer += chunk;

            // SSE 형식: "data: {...}\n\n"
            while (buffer.contains('\n\n')) {
              final idx = buffer.indexOf('\n\n');
              final message = buffer.substring(0, idx).trim();
              buffer = buffer.substring(idx + 2);

              if (message.startsWith('data: ')) {
                final jsonStr = message.substring(6);
                try {
                  final json = jsonDecode(jsonStr);
                  if (json is Map<String, dynamic>) {
                    controller.add(SseEvent.fromJson(json));
                  }
                } catch (e) {
                  debugPrint('[ApiClient] SSE parse error: $e');
                }
              }
            }
          }
        } catch (e) {
          if (!cancelled) {
            debugPrint('[ApiClient] SSE connection error: $e');
          }
        }

        // 재연결 대기 (3초)
        if (!cancelled) {
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }();

    return controller.stream;
  }

  // ─── 내부 HTTP 헬퍼 ───

  Future<dynamic> _get(String path) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(Uri.parse('$baseUrl$path'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return jsonDecode(body);
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('$baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    await response.drain();
    client.close();
  }

  Future<void> _delete(String path) async {
    final client = HttpClient();
    final request = await client.deleteUrl(Uri.parse('$baseUrl$path'));
    final response = await request.close();
    await response.drain();
    client.close();
  }
}

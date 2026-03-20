import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_client.dart' show Device;

/// matterjs-server WS 직접 연결 클라이언트 — 예비용 (현재 미사용)
///
/// 아키텍처 결정 (2026-03-20):
/// 앱은 Go REST만 통신한다. matterjs WS 직접 연결은 하지 않는다.
/// Go 서버가 단일 진입점으로서 상태 관리 + aliases + SSE 변환을 전담.
///
/// 이 파일은 향후 "Go 없는 경량 모드" 또는 "디버깅용 직접 연결"을 위해 보존.
/// 조급함에 이중 경로(APP→Go + APP→matterjs)를 도입할 뻔했으나,
/// 단일 경로(APP→Go→matterjs)가 구조적으로 올바른 판단.
///
/// Go matter/client.go와 동일한 프로토콜:
/// - 연결 시 첫 메시지 = ServerInfo (JSON)
/// - 명령: {"message_id":"ha-1","command":"get_nodes"} → 응답 {"message_id":"ha-1","result":[...]}
/// - 이벤트: {"event":"attribute_updated","data":[nodeId, path, value]}
/// - 이벤트: {"event":"node_added","data":{...}}
///
/// ReadLoop 패턴: 단일 listen에서 응답/이벤트 분배
class MatterWsClient {
  final String url; // ws://host:5580

  WebSocket? _ws;
  int _messageId = 0;
  ServerInfo? _info;

  // 응답 대기 맵
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  // 이벤트 스트림
  final StreamController<MatterEvent> _eventController =
      StreamController.broadcast();

  // 연결 상태
  final ValueNotifier<bool> connected = ValueNotifier(false);

  MatterWsClient({required this.url});

  ServerInfo? get info => _info;
  Stream<MatterEvent> get events => _eventController.stream;

  /// 연결 + ServerInfo 수신 + ReadLoop 시작
  Future<void> connect() async {
    final wsUrl = url.replaceFirst(RegExp(r'^http'), 'ws');
    _ws = await WebSocket.connect('$wsUrl/ws');
    connected.value = true;

    // ReadLoop: 첫 메시지 = ServerInfo, 이후 응답/이벤트
    bool firstMessage = true;
    _ws!.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;

        if (firstMessage) {
          firstMessage = false;
          _info = ServerInfo.fromJson(json);
          debugPrint('[MatterWS] connected: ${_info!.sdkVersion} '
              '(fabric=${_info!.fabricId}, ble=${_info!.bluetoothEnabled})');
          return;
        }

        _dispatch(json);
      },
      onDone: () {
        connected.value = false;
        debugPrint('[MatterWS] disconnected');
        _failAllPending('connection closed');
      },
      onError: (e) {
        connected.value = false;
        debugPrint('[MatterWS] error: $e');
        _failAllPending('connection error: $e');
      },
    );
  }

  void _dispatch(Map<String, dynamic> json) {
    // 응답 (has message_id)
    final msgId = json['message_id'] as String?;
    if (msgId != null && _pending.containsKey(msgId)) {
      _pending.remove(msgId)!.complete(json);
      return;
    }

    // 이벤트 (has event field)
    final eventType = json['event'] as String?;
    if (eventType != null) {
      _eventController.add(MatterEvent(
        type: eventType,
        data: json['data'],
      ));
      return;
    }

    debugPrint('[MatterWS] unknown: ${json.toString().substring(0, 200.clamp(0, json.toString().length))}');
  }

  void _failAllPending(String reason) {
    for (final c in _pending.values) {
      c.completeError(reason);
    }
    _pending.clear();
  }

  String _nextId() => 'ha-${++_messageId}';

  /// 명령 전송 + 응답 대기
  Future<Map<String, dynamic>> _send(String command,
      [Map<String, dynamic>? args, Duration timeout = const Duration(seconds: 30)]) async {
    if (_ws == null) throw StateError('Not connected');

    final id = _nextId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final msg = <String, dynamic>{
      'message_id': id,
      'command': command,
    };
    if (args != null) msg['args'] = args;
    _ws!.add(jsonEncode(msg));

    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('$command timeout', timeout);
    });
  }

  /// 응답에서 result 추출 (에러 체크 포함)
  dynamic _result(Map<String, dynamic> resp) {
    final errorCode = resp['error_code'] as int? ?? 0;
    if (errorCode != 0) {
      throw Exception('${resp['command'] ?? 'command'} error $errorCode: ${resp['details']}');
    }
    return resp['result'];
  }

  // ─── Matter 명령 ───

  /// 이벤트 구독 시작
  Future<void> startListening() async {
    final resp = await _send('start_listening');
    _result(resp);
    debugPrint('[MatterWS] start_listening active');
  }

  /// 전체 노드 목록 → Device 리스트로 변환
  Future<List<Device>> getNodes() async {
    final resp = await _send('get_nodes');
    final nodes = _result(resp) as List;
    return nodes.map((n) => nodeToDevice(n as Map<String, dynamic>)).toList();
  }

  /// 디바이스 명령 (on/off, level 등)
  Future<void> deviceCommand({
    required int nodeId,
    required int endpointId,
    required int clusterId,
    required String commandName,
    Map<String, dynamic>? payload,
  }) async {
    final args = <String, dynamic>{
      'node_id': nodeId,
      'endpoint_id': endpointId,
      'cluster_id': clusterId,
      'command_name': commandName,
    };
    if (payload != null) args['payload'] = payload;
    final resp = await _send('device_command', args, const Duration(seconds: 15));
    _result(resp);
  }

  /// 편의: on/off 토글 (OnOff cluster = 6, endpoint 1)
  Future<void> toggleOnOff(int nodeId, bool on) async {
    await deviceCommand(
      nodeId: nodeId,
      endpointId: 1,
      clusterId: 6,
      commandName: on ? 'on' : 'off',
    );
  }

  /// 편의: 밝기 조절 (LevelControl cluster = 8)
  Future<void> setLevel(int nodeId, int level) async {
    await deviceCommand(
      nodeId: nodeId,
      endpointId: 1,
      clusterId: 8,
      commandName: 'move_to_level_with_on_off',
      payload: {'level': level, 'transition_time': 5},
    );
  }

  /// Setup code로 커미셔닝
  Future<Device> commissionWithCode(String code, {bool networkOnly = false}) async {
    final args = <String, dynamic>{'code': code};
    if (networkOnly) args['network_only'] = true;
    final resp = await _send('commission_with_code', args, const Duration(seconds: 180));
    final node = _result(resp) as Map<String, dynamic>;
    return nodeToDevice(node);
  }

  /// On-network 커미셔닝 (PIN + optional IP)
  Future<Device> commissionOnNetwork(int pinCode, {String? ipAddr}) async {
    final args = <String, dynamic>{'setup_pin_code': pinCode};
    if (ipAddr != null) args['ip_addr'] = ipAddr;
    final resp = await _send('commission_on_network', args, const Duration(seconds: 120));
    final node = _result(resp) as Map<String, dynamic>;
    return nodeToDevice(node);
  }

  /// WiFi credentials 설정
  Future<void> setWifiCredentials(String ssid, String password) async {
    final resp = await _send('set_wifi_credentials', {
      'ssid': ssid,
      'credentials': password,
    }, const Duration(seconds: 10));
    _result(resp);
  }

  /// Thread dataset 설정
  Future<void> setThreadDataset(String dataset) async {
    final resp = await _send('set_thread_dataset', {
      'dataset': dataset,
    }, const Duration(seconds: 10));
    _result(resp);
  }

  /// 노드 삭제
  Future<void> removeNode(int nodeId) async {
    final resp = await _send('remove_node', {'node_id': nodeId},
        const Duration(seconds: 15));
    _result(resp);
  }

  /// 연결 종료
  void close() {
    _ws?.close();
    _ws = null;
    connected.value = false;
    _failAllPending('closed');
  }

  // ─── Node → Device 변환 ───
  //
  // matterjs Node 구조를 Flutter Device 모델로 변환.
  // attributes에서 type/state 추출.

  /// @visibleForTesting
  static Device nodeToDevice(Map<String, dynamic> node) {
    final nodeId = node['node_id'] as int? ?? 0;
    final available = node['available'] as bool? ?? false;
    final rawAttrs = node['attributes'];
    final attrs = rawAttrs is Map ? Map<String, dynamic>.from(rawAttrs) : <String, dynamic>{};

    // 디바이스 타입 추출 (DeviceType cluster)
    String type = '';
    for (final key in attrs.keys) {
      // "1/29/0" = endpoint 1, cluster 29 (Descriptor), attr 0 (DeviceTypeList)
      if (key.contains('/29/0')) {
        final val = attrs[key];
        if (val is List && val.isNotEmpty) {
          final deviceType = val[0];
          if (deviceType is Map) {
            type = _mapDeviceType(deviceType['deviceType'] as int? ?? 0);
          }
        }
      }
    }

    // 상태 추출
    final state = <String, dynamic>{};

    // OnOff (cluster 6, attr 0)
    for (final key in attrs.keys) {
      if (key.endsWith('/6/0')) {
        state['on'] = attrs[key] == true;
      }
    }

    // LevelControl (cluster 8, attr 0 = currentLevel)
    for (final key in attrs.keys) {
      if (key.endsWith('/8/0')) {
        state['level'] = attrs[key];
      }
    }

    // ColorControl (cluster 768, attr 7 = colorTempMireds)
    for (final key in attrs.keys) {
      if (key.endsWith('/768/7')) {
        state['color_temp'] = attrs[key];
      }
    }

    // Temperature (cluster 1026, attr 0 = measuredValue) → /100
    for (final key in attrs.keys) {
      if (key.endsWith('/1026/0')) {
        final raw = attrs[key];
        if (raw is num) state['temperature'] = raw / 100.0;
      }
    }

    // Humidity (cluster 1029, attr 0)
    for (final key in attrs.keys) {
      if (key.endsWith('/1029/0')) {
        final raw = attrs[key];
        if (raw is num) state['humidity'] = raw / 100.0;
      }
    }

    // BooleanState / Contact (cluster 69, attr 0)
    for (final key in attrs.keys) {
      if (key.endsWith('/69/0')) {
        state['contact'] = attrs[key] == true;
      }
    }

    return Device(
      nodeId: nodeId,
      name: 'Node $nodeId',
      type: type,
      available: available,
      state: state,
    );
  }

  /// Matter device type ID → 문자열 타입명
  static String _mapDeviceType(int id) {
    switch (id) {
      case 0x010A: return 'on_off_plug';
      case 0x0100: return 'on_off_light';
      case 0x0101: return 'dimmable_light';
      case 0x010C: return 'color_temp_light';
      case 0x010D: return 'extended_color_light';
      case 0x0302: return 'temperature_sensor';
      case 0x0307: return 'humidity_sensor';
      case 0x0015: return 'contact_sensor';
      default: return 'unknown_$id';
    }
  }
}

/// matterjs-server WS 이벤트
class MatterEvent {
  final String type; // attribute_updated, node_added, node_updated, node_removed
  final dynamic data;

  MatterEvent({required this.type, required this.data});

  /// attribute_updated 파싱: [nodeId, path, value]
  ({int nodeId, String path, dynamic value})? get attributeUpdate {
    if (type != 'attribute_updated' || data is! List || (data as List).length < 3) {
      return null;
    }
    final arr = data as List;
    return (
      nodeId: arr[0] as int,
      path: arr[1] as String,
      value: arr[2],
    );
  }
}

/// matterjs-server 초기 정보
class ServerInfo {
  final int fabricId;
  final int fabricIndex;
  final int schemaVersion;
  final String sdkVersion;
  final bool bluetoothEnabled;
  final bool threadCredentialsSet;

  ServerInfo({
    required this.fabricId,
    required this.fabricIndex,
    required this.schemaVersion,
    required this.sdkVersion,
    required this.bluetoothEnabled,
    required this.threadCredentialsSet,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      fabricId: json['fabric_id'] ?? 0,
      fabricIndex: json['fabric_index'] ?? 0,
      schemaVersion: json['schema_version'] ?? 0,
      sdkVersion: json['sdk_version'] ?? '',
      bluetoothEnabled: json['bluetooth_enabled'] ?? false,
      threadCredentialsSet: json['thread_credentials_set'] ?? false,
    );
  }
}

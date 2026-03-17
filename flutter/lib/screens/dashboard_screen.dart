import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart' show GenUiSurface;

import '../a2ui_adapter.dart';
import '../api_client.dart';
import '../theme.dart';
import '../widgets/device_card.dart';
import '../widgets/quick_status.dart';

/// 대시보드 — A2UI Surface + 디바이스 그리드 + SSE 실시간 갱신
class DashboardScreen extends StatefulWidget {
  final String serverUrl;
  const DashboardScreen({super.key, required this.serverUrl});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiClient _api;
  late final HomeAgentA2uiAdapter _a2ui;
  List<Device> _devices = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.serverUrl);
    _a2ui = HomeAgentA2uiAdapter(api: _api);
    _fetchAll();
    _connectSse();
    _a2ui.fetchAndRender();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    try {
      final devices = await _api.getDevices();
      setState(() {
        _devices = devices;
        _loading = false;
        _error = null;
      });
      // A2UI Surface 새로고침
      _a2ui.fetchAndRender();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _connectSse() {
    _sseSub = _api.eventStream().listen(
      (event) {
        switch (event.type) {
          case 'snapshot':
            // 초기 스냅샷 — rawJson에서 devices 추출 (value가 아닌 최상위)
            final raw = event.rawJson;
            final devicesRaw = raw['devices'] ?? event.value?['devices'];
            if (devicesRaw is List) {
              final list = devicesRaw
                  .map((d) =>
                      Device.fromJson(Map<String, dynamic>.from(d)))
                  .toList();
              debugPrint('[Dashboard] SSE snapshot: ${list.length} devices');
              setState(() {
                _devices = list;
                _error = null;
              });
            } else {
              debugPrint('[Dashboard] SSE snapshot: devices not found in raw=$raw');
            }
            break;
          case 'device_state':
            debugPrint('[Dashboard] SSE device_state: node=${event.deviceId} key=${event.key} value=${event.value}');
            _handleDeviceState(event);
            break;
          case 'device_added':
            // 디바이스 추가 — 목록 새로고침
            _fetchAll();
            break;
          case 'device_removed':
            setState(() {
              _devices.removeWhere((d) => d.nodeId == event.deviceId);
            });
            break;
          case 'surface_update':
            if (event.value is Map) {
              _a2ui.handleSurfaceUpdate(
                  Map<String, dynamic>.from(event.value));
            }
            break;
        }
      },
      onError: (e) {
        debugPrint('[Dashboard] SSE error: $e');
      },
    );
  }

  // Matter attribute path → state key (Go attrMap 미러)
  static const _attrMap = {
    '1/6/0': 'on',
    '1/8/0': 'level',
    '1/768/7': 'color_temp',
    '1/1026/0': 'temperature',
    '1/1029/0': 'humidity',
    '1/69/0': 'contact',
  };

  void _handleDeviceState(SseEvent event) {
    setState(() {
      final idx = _devices.indexWhere((d) => d.nodeId == event.deviceId);
      if (idx >= 0) {
        final old = _devices[idx];
        final newState = Map<String, dynamic>.from(old.state);
        if (event.key.isNotEmpty) {
          final mappedKey = _attrMap[event.key] ?? event.key;
          newState[mappedKey] = event.value;
          debugPrint('[Dashboard] state update: node=${old.nodeId} $mappedKey=${event.value}');
        }
        _devices[idx] = Device(
          nodeId: old.nodeId,
          name: old.name,
          room: old.room,
          type: old.type,
          available: event.key == 'available'
              ? (event.value == true)
              : old.available,
          state: newState,
        );
      }
    });
  }

  void _onCommand(int nodeId, String command, {dynamic value}) {
    _api.sendCommand(nodeId, command, value: value).then((_) {
      // SSE의 key가 원시 path("1/6/0")로 오는 문제 우회:
      // 명령 후 짧은 딜레이 뒤 전체 디바이스 새로고침
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _fetchAll();
      });
    }).catchError((e) {
      debugPrint('[Dashboard] command error: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT Hub'),
        actions: [
          // 연결 상태 칩
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(
                _error == null ? Icons.cloud_done : Icons.cloud_off,
                size: 16,
                color: _error == null ? AppTheme.green : AppTheme.errorColor,
              ),
              label: Text(
                _error == null ? '연결됨' : '오프라인',
                style: const TextStyle(fontSize: 12),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAll,
        child: CustomScrollView(
          slivers: [
            // 에러 배너
            if (_error != null)
              SliverToBoxAdapter(
                child: MaterialBanner(
                  content: Text(_error!),
                  backgroundColor:
                      Theme.of(context).colorScheme.errorContainer,
                  actions: [
                    TextButton(
                      onPressed: _fetchAll,
                      child: const Text('재시도'),
                    ),
                  ],
                ),
              ),

            // A2UI Home Surface (시간 카드 + 디바이스 요약)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: GenUiSurface(
                  host: _a2ui.host,
                  surfaceId: 'home',
                  defaultBuilder: (_) {
                    debugPrint('[Dashboard] GenUiSurface defaultBuilder — surface not ready yet');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Surface 로딩 중...',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 상태 요약
            SliverToBoxAdapter(
              child: QuickStatus(devices: _devices),
            ),

            // 디바이스 그리드
            if (_devices.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.devices, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('디바이스 없음',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => DeviceCard(
                      device: _devices[index],
                      onCommand: _onCommand,
                    ),
                    childCount: _devices.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

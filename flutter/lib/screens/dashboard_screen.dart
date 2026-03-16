import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../widgets/device_card.dart';
import '../widgets/quick_status.dart';

/// 대시보드 — 디바이스 그리드 + SSE 실시간 갱신
/// shell_native.dart에서 리팩터링: API→ApiClient, 폴링→SSE, ListView→GridView
class DashboardScreen extends StatefulWidget {
  final String serverUrl;
  const DashboardScreen({super.key, required this.serverUrl});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiClient _api;
  List<Device> _devices = [];
  Map<String, dynamic>? _home;
  bool _loading = true;
  String? _error;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.serverUrl);
    _fetchAll();
    _connectSse();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    try {
      final results = await Future.wait([
        _api.getDevices(),
        _api.getHome(),
      ]);
      setState(() {
        _devices = results[0] as List<Device>;
        _home = results[1] as Map<String, dynamic>?;
        _loading = false;
        _error = null;
      });
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
            // 초기 스냅샷 — 전체 디바이스 목록
            if (event.value is Map && event.value['devices'] is List) {
              final list = (event.value['devices'] as List)
                  .map((d) =>
                      Device.fromJson(Map<String, dynamic>.from(d)))
                  .toList();
              setState(() {
                _devices = list;
                _error = null;
              });
            }
            break;
          case 'device_state':
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
        }
      },
      onError: (e) {
        debugPrint('[Dashboard] SSE error: $e');
      },
    );
  }

  void _handleDeviceState(SseEvent event) {
    setState(() {
      final idx = _devices.indexWhere((d) => d.nodeId == event.deviceId);
      if (idx >= 0) {
        final old = _devices[idx];
        final newState = Map<String, dynamic>.from(old.state);
        if (event.key.isNotEmpty) {
          newState[event.key] = event.value;
        }
        _devices[idx] = Device(
          nodeId: old.nodeId,
          name: old.name,
          room: old.room,
          type: old.type,
          available: old.available,
          state: newState,
        );
      }
    });
  }

  void _onCommand(int nodeId, String command, {dynamic value}) {
    _api.sendCommand(nodeId, command, value: value).catchError((e) {
      debugPrint('[Dashboard] command error: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final greeting = _home?['greeting'] ?? 'IoT Hub';

    return Scaffold(
      appBar: AppBar(
        title: Text(greeting),
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

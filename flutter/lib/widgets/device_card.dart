import 'package:flutter/material.dart';

import '../api_client.dart';
import '../screens/device_detail_screen.dart';
import '../theme.dart';

/// 디바이스 카드 — 3열 그리드용
/// 타입별 아이콘/색상/제어 분기
/// 탭 → 상세 화면, 롱프레스 → 삭제, 토글스위치 → on/off
class DeviceCard extends StatelessWidget {
  final Device device;
  final String serverUrl;
  final void Function(int nodeId, String command, {dynamic value})? onCommand;
  final void Function(int nodeId)? onDelete;

  const DeviceCard({
    super.key,
    required this.device,
    this.serverUrl = '',
    this.onCommand,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: serverUrl.isEmpty
            ? null
            : () async {
                final deleted = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceDetailScreen(
                      serverUrl: serverUrl,
                      device: device,
                    ),
                  ),
                );
                if (deleted == true) onDelete?.call(device.nodeId);
              },
        onLongPress: onDelete == null
            ? null
            : () => _showDeleteDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 아이콘 + 상태 인디케이터
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(_icon, color: _iconColor, size: 32),
                  if (!device.available)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.cloud_off, size: 14, color: AppTheme.errorColor),
                      ],
                    )
                  else if (!device.isSensor)
                    SizedBox(
                      height: 24,
                      child: Switch(
                        value: device.isOn,
                        onChanged: (v) => onCommand?.call(
                          device.nodeId,
                          v ? 'on' : 'off',
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              // 센서 큰 값 표시
              if (device.isContactSensor) ...[
                const Spacer(),
                Icon(
                  device.contactOpen ? Icons.door_front_door : Icons.door_front_door_outlined,
                  size: 28,
                  color: device.contactOpen ? AppTheme.openColor : AppTheme.closedColor,
                ),
              ] else if (device.isTemperatureSensor) ...[
                const Spacer(),
                Text(
                  device.state['temperature'] != null
                      ? '${device.state['temperature']}°'
                      : '--',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.blue,
                  ),
                ),
              ] else if (device.isHumiditySensor) ...[
                const Spacer(),
                Text(
                  device.state['humidity'] != null
                      ? '${device.state['humidity']}%'
                      : '--',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.blue,
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],
              // 이름
              Text(
                device.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // 방 + 상태
              Text(
                _subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(153),
                ),
                maxLines: 1,
              ),
              // 밝기 슬라이더 (dimmable만)
              if (device.isDimmable && device.isOn && device.available)
                _buildLevelSlider(theme),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon {
    switch (device.type) {
      case 'contact_sensor':
        return Icons.sensor_door;
      case 'temperature_sensor':
        return Icons.thermostat;
      case 'humidity_sensor':
        return Icons.water_drop;
      case 'on_off_light':
      case 'dimmable_light':
      case 'color_temp_light':
      case 'extended_color_light':
        return Icons.lightbulb;
      case 'on_off_plug':
        return Icons.power;
      default:
        return Icons.devices_other;
    }
  }

  Color get _iconColor {
    if (!device.available) return AppTheme.errorColor;
    if (device.isContactSensor) {
      return device.contactOpen ? AppTheme.openColor : AppTheme.closedColor;
    }
    if (device.isTemperatureSensor || device.isHumiditySensor) {
      return AppTheme.blue;
    }
    return device.isOn ? AppTheme.onColor : AppTheme.offColor;
  }

  String get _subtitle {
    if (!device.available) {
      return device.room.isNotEmpty ? '${device.room} · 연결 중...' : '연결 중...';
    }
    final parts = <String>[];
    if (device.room.isNotEmpty) parts.add(device.room);
    if (device.isContactSensor) {
      parts.add(device.contactOpen ? '🔓 열림' : '🔒 닫힘');
    } else if (device.isTemperatureSensor) {
      final temp = device.state['temperature'];
      final humidity = device.state['humidity'];
      if (temp != null) parts.add('${temp}°C');
      if (humidity != null) parts.add('${humidity}%');
    } else if (device.isHumiditySensor) {
      final humidity = device.state['humidity'];
      if (humidity != null) parts.add('${humidity}%');
    } else {
      parts.add(device.isOn ? '켜짐' : '꺼짐');
      if (device.isDimmable && device.isOn) {
        parts.add('${device.level}%');
      }
    }
    return parts.join(' · ');
  }

  Widget _buildLevelSlider(ThemeData theme) {
    return SizedBox(
      height: 24,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: AppTheme.onColor,
          inactiveTrackColor: AppTheme.onColor.withAlpha(51),
          thumbColor: AppTheme.onColor,
        ),
        child: Slider(
          value: device.level.toDouble().clamp(0, 100),
          min: 0,
          max: 100,
          onChangeEnd: (v) => onCommand?.call(
            device.nodeId,
            'set_level',
            value: v.round(),
          ),
          onChanged: (_) {},
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${device.name} 삭제'),
        content: Text(
          '노드 ${device.nodeId}을 삭제하시겠습니까?\n\n'
          '디바이스가 오프라인이면 공장초기화 후\n재페어링이 필요합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call(device.nodeId);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

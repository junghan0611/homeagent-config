import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 백엔드 프로세스 매니저 — Go homeagent + Node.js matterjs-server
///
/// 플랫폼별 동작:
/// - **Yocto (RPi5)**: systemd가 관리 → 프로세스 시작 안 함, healthcheck만
/// - **Android (번들)**: Flutter가 직접 프로세스 시작/종료
///
/// 번들 디렉토리 구조 (Android assets → app files에 복사):
///   /data/data/<pkg>/files/backend/
///   ├── homeagent           (Go 바이너리)
///   ├── node/bin/node       (Node.js 바이너리)
///   ├── matterjs-server/    (npm 패키지)
///   ├── ui/                 (Lit 프론트엔드)
///   └── aliases.json
class BackendProcess {
  Process? _goProcess;
  Process? _nodeProcess;
  final String bundlePath;
  final int goPort;
  final int matterPort;

  bool _running = false;
  bool get isRunning => _running;

  String get healthUrl => 'http://localhost:$goPort/healthz';

  BackendProcess({
    required this.bundlePath,
    this.goPort = 8080,
    this.matterPort = 5580,
  });

  /// 백엔드 시작 (Android 번들 모드)
  ///
  /// 1. matterjs-server 시작 (Node.js)
  /// 2. 3초 대기
  /// 3. Go homeagent 시작
  /// 4. healthcheck 대기
  Future<void> start() async {
    if (_running) return;

    final nodeBin = '$bundlePath/node/bin/node';
    final matterEntry =
        '$bundlePath/matterjs-server/node_modules/matter-server/dist/esm/MatterServer.js';
    final goBin = '$bundlePath/homeagent';
    final storagePath = '$bundlePath/data/matter';

    // 데이터 디렉토리 생성
    await Directory(storagePath).create(recursive: true);

    // 실행 권한 확인 (Android에서 assets 복사 후 필요)
    await _ensureExecutable(goBin);
    await _ensureExecutable(nodeBin);

    debugPrint('[backend] matterjs-server 시작 (port $matterPort)...');

    // 1. matterjs-server
    _nodeProcess = await Process.start(
      nodeBin,
      [
        matterEntry,
        '--storage-path',
        storagePath,
        '--port',
        matterPort.toString(),
      ],
      workingDirectory: bundlePath,
      environment: {
        'HOME': bundlePath,
        'NODE_ENV': 'production',
      },
    );
    _pipeOutput(_nodeProcess!, 'matter');

    // 2. 대기
    await Future.delayed(const Duration(seconds: 3));

    debugPrint('[backend] homeagent 시작 (port $goPort)...');

    // 3. Go homeagent
    _goProcess = await Process.start(
      goBin,
      [],
      workingDirectory: bundlePath,
      environment: {
        'HOMEAGENT_HTTP_ADDR': ':$goPort',
        'HOMEAGENT_WS_URL': 'ws://localhost:$matterPort/ws',
        'HOMEAGENT_UI_DIR': '$bundlePath/ui',
        'HOMEAGENT_ALIASES_FILE': '$bundlePath/aliases.json',
        'HOME': bundlePath,
      },
    );
    _pipeOutput(_goProcess!, 'go');

    _running = true;

    // 4. healthcheck 대기
    await _waitForHealth();

    debugPrint('[backend] 백엔드 준비 완료');
  }

  /// 백엔드 종료
  Future<void> stop() async {
    debugPrint('[backend] 종료 중...');
    _running = false;

    _goProcess?.kill(ProcessSignal.sigterm);
    _nodeProcess?.kill(ProcessSignal.sigterm);

    // graceful shutdown 대기
    await Future.wait([
      if (_goProcess != null) _goProcess!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _goProcess?.kill(ProcessSignal.sigkill);
          return -1;
        },
      ),
      if (_nodeProcess != null) _nodeProcess!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _nodeProcess?.kill(ProcessSignal.sigkill);
          return -1;
        },
      ),
    ]);

    _goProcess = null;
    _nodeProcess = null;
    debugPrint('[backend] 종료 완료');
  }

  /// 외부 서버 healthcheck (Yocto/원격 모드)
  Future<bool> checkHealth() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse(healthUrl));
      final response = await request.close();
      await response.drain();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// healthcheck 대기 (최대 30초)
  Future<void> _waitForHealth() async {
    for (int i = 0; i < 30; i++) {
      if (await checkHealth()) return;
      await Future.delayed(const Duration(seconds: 1));
    }
    throw Exception('백엔드 시작 실패: healthcheck 30초 타임아웃');
  }

  /// 프로세스 stdout/stderr를 debugPrint로 파이프
  void _pipeOutput(Process process, String tag) {
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((line) => debugPrint('[$tag] $line'));
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((line) => debugPrint('[$tag:err] $line'));

    // 비정상 종료 감지
    process.exitCode.then((code) {
      if (_running) {
        debugPrint('[$tag] 프로세스 비정상 종료 (code=$code)');
      }
    });
  }

  /// 파일 실행 권한 부여
  Future<void> _ensureExecutable(String path) async {
    if (Platform.isAndroid || Platform.isLinux) {
      await Process.run('chmod', ['+x', path]);
    }
  }
}

/// 플랫폼 감지 — 번들 모드 vs 외부 서버 모드
enum BackendMode {
  /// Android: Flutter가 번들 내 프로세스를 직접 관리
  bundle,

  /// Yocto/개발: systemd 또는 수동 실행된 외부 서버에 연결
  external,
}

BackendMode detectBackendMode() {
  // Android에서는 번들 모드
  if (Platform.isAndroid) return BackendMode.bundle;
  // Linux (Yocto/개발)에서는 외부 모드
  return BackendMode.external;
}

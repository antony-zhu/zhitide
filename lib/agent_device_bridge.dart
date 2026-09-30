import 'package:flutter/services.dart';

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.accessibilityEnabled,
    required this.termuxInstalled,
    required this.termuxPermissionGranted,
  });

  final bool accessibilityEnabled;
  final bool termuxInstalled;
  final bool termuxPermissionGranted;
}

class PhoneObservation {
  const PhoneObservation({
    required this.screenshotBase64,
    required this.width,
    required this.height,
    required this.nodes,
  });

  final String screenshotBase64;
  final int width;
  final int height;
  final List<Map<String, dynamic>> nodes;
}

class PhoneCommandResult {
  const PhoneCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
}

class AgentDeviceBridge {
  const AgentDeviceBridge();

  static const _channel = MethodChannel('com.example.zhixi/agent');

  Future<DeviceCapabilities> capabilities() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'capabilities',
    );
    if (result == null) throw StateError('无法读取手机操作状态');
    return DeviceCapabilities(
      accessibilityEnabled: result['accessibilityEnabled'] == true,
      termuxInstalled: result['termuxInstalled'] == true,
      termuxPermissionGranted: result['termuxPermissionGranted'] == true,
    );
  }

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  Future<bool> requestTermuxPermission() async =>
      await _channel.invokeMethod<bool>('requestTermuxPermission') == true;

  Future<void> openTermux() => _channel.invokeMethod<void>('openTermux');

  Future<PhoneObservation> observe() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('observe');
    if (result == null) throw StateError('无法读取手机画面');
    final rawNodes = result['nodes'];
    return PhoneObservation(
      screenshotBase64: result['screenshotBase64'] as String,
      width: result['width'] as int,
      height: result['height'] as int,
      nodes: rawNodes is List
          ? rawNodes
                .map((node) => Map<String, dynamic>.from(node as Map))
                .toList()
          : const [],
    );
  }

  Future<void> tap(int x, int y) => _action('tap', {'x': x, 'y': y});

  Future<void> swipe(int x1, int y1, int x2, int y2, int durationMs) => _action(
    'swipe',
    {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'durationMs': durationMs},
  );

  Future<void> typeText(String value) => _action('typeText', {'text': value});

  Future<void> globalAction(String action) =>
      _action('globalAction', {'action': action});

  Future<PhoneCommandResult> runCommand(String command, {String? stdin}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'runCommand',
      {'command': command, 'stdin': stdin},
    );
    if (result == null) throw StateError('未收到命令结果');
    return PhoneCommandResult(
      stdout: result['stdout'] as String? ?? '',
      stderr: result['stderr'] as String? ?? '',
      exitCode: result['exitCode'] as int? ?? -1,
    );
  }

  Future<void> _action(String name, Map<String, dynamic> arguments) async {
    final completed = await _channel.invokeMethod<bool>(name, arguments);
    if (completed != true) throw StateError('手机操作没有完成');
  }
}

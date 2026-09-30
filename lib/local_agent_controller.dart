import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'agent_api.dart';
import 'agent_device_bridge.dart';
import 'api_key_store.dart';
import 'chat_preferences.dart';

enum LocalTaskStatus {
  idle,
  running,
  waitingApproval,
  completed,
  stopped,
  failed,
}

class LocalTaskStep {
  const LocalTaskStep({required this.title, required this.detail});

  final String title;
  final String detail;
}

class LocalTaskApproval {
  const LocalTaskApproval({required this.title, required this.detail});

  final String title;
  final String detail;
}

class LocalAgentController extends ChangeNotifier {
  LocalAgentController({
    required this.api,
    required this.device,
    required this.keyStore,
    required this.prefsStore,
  });

  final AgentApi api;
  final AgentDeviceBridge device;
  final ApiKeyStore keyStore;
  final ChatPreferencesStore prefsStore;

  LocalTaskStatus status = LocalTaskStatus.idle;
  DeepSeekModel taskModel = DeepSeekModel.flash;
  DeepSeekModel activeModel = DeepSeekModel.flash;
  DeviceCapabilities? capabilities;
  String? setupError;
  String? error;
  LocalTaskApproval? pendingApproval;
  final List<LocalTaskStep> steps = [];

  Completer<bool>? _approvalResponse;
  bool _stopRequested = false;

  bool get isActive =>
      status == LocalTaskStatus.running ||
      status == LocalTaskStatus.waitingApproval;

  Future<void> refreshTaskModel() async {
    final preferences = await prefsStore.read();
    taskModel = preferences.taskModel;
    if (status == LocalTaskStatus.idle) activeModel = taskModel;
    notifyListeners();
  }

  Future<void> selectTaskModel(DeepSeekModel model) async {
    if (isActive) return;
    final preferences = await prefsStore.read();
    await prefsStore.write(preferences.copyWith(taskModel: model));
    taskModel = model;
    activeModel = model;
    notifyListeners();
  }

  Future<void> refreshCapabilities() async {
    try {
      capabilities = await device.capabilities();
      setupError = null;
    } catch (_) {
      setupError = '无法检查手机操作权限与 Termux 状态。';
    }
    notifyListeners();
  }

  Future<void> startTask(String instruction) async {
    final task = instruction.trim();
    if (task.isEmpty || isActive) return;

    _stopRequested = false;
    pendingApproval = null;
    _approvalResponse = null;
    steps.clear();
    error = null;
    activeModel = taskModel;
    status = LocalTaskStatus.running;
    _addStep('任务已开始', task);

    try {
      final apiKey = (await keyStore.read())?.trim();
      if (apiKey == null || apiKey.isEmpty) {
        throw StateError('请先在模型设置中保存 DeepSeek API Key。');
      }
      final current = await device.capabilities();
      capabilities = current;
      notifyListeners();
      if (!current.termuxInstalled) {
        throw StateError('请先安装并打开 Termux。');
      }
      if (!current.termuxPermissionGranted) {
        throw StateError('请在知汐的应用权限中允许“在 Termux 中运行命令”。');
      }
      final preferences = await prefsStore.read();
      taskModel = preferences.taskModel;
      activeModel = taskModel;
      notifyListeners();
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': task},
      ];
      var hasFreshScreen = false;

      for (var turnCount = 0; turnCount < 24; turnCount++) {
        if (_stopRequested) return;
        final turn = await api.complete(
          apiKey: apiKey,
          model: activeModel.apiId,
          messages: messages,
          tools: _tools,
          thinkingEnabled: preferences.thinkingEnabled,
        );
        if (_stopRequested) return;
        messages.add(turn.assistantMessage);
        final content = turn.content?.trim();
        if (content != null && content.isNotEmpty) {
          _addStep(turn.toolCalls.isEmpty ? '任务回复' : '正在处理', content);
        }
        if (turn.toolCalls.isEmpty) {
          status = LocalTaskStatus.completed;
          notifyListeners();
          return;
        }

        PhoneObservation? observation;
        var observedThisTurn = false;
        final screenReadyAtTurnStart = hasFreshScreen;
        for (final call in turn.toolCalls) {
          if (_stopRequested) return;
          final isScreenAction =
              call.name == 'tap_screen' ||
              call.name == 'swipe_screen' ||
              call.name == 'type_text' ||
              call.name == 'press_back' ||
              call.name == 'press_home';
          _ToolResult result;
          if (isScreenAction &&
              (!screenReadyAtTurnStart ||
                  observedThisTurn ||
                  !hasFreshScreen)) {
            _addStep('需要重新观察屏幕', '请先查看截图，再决定下一步界面操作。');
            result = const _ToolResult(
              output: {'ok': false, 'error': '请先读取新的屏幕截图再操作'},
            );
          } else {
            result = await _execute(call);
            if (isScreenAction) hasFreshScreen = false;
            if (call.name == 'observe_screen' && result.observation != null) {
              observedThisTurn = true;
              hasFreshScreen = true;
            }
          }
          if (_stopRequested) return;
          if (result.observation != null) observation = result.observation;
          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': jsonEncode(result.output),
          });
        }
        if (observation != null) {
          if (activeModel == DeepSeekModel.pro) {
            activeModel = DeepSeekModel.flash;
            notifyListeners();
          }
          for (final message in messages) {
            if (message['content'] is List && message['role'] == 'user') {
              message['content'] = '此前已查看的手机画面。';
            }
          }
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '这是刚才读取的当前屏幕。点击和滑动坐标按整张图从 0 到 1000 归一化。',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url':
                      'data:image/jpeg;base64,${observation.screenshotBase64}',
                },
              },
            ],
          });
        }
      }
      throw StateError('已达到本次任务的步骤上限，请缩小任务范围后重试。');
    } catch (failure) {
      if (_stopRequested) return;
      error = _readableError(failure);
      status = LocalTaskStatus.failed;
      _addStep('任务未完成', error!);
    }
  }

  void stop() {
    if (!isActive) return;
    _stopRequested = true;
    if (_approvalResponse != null && !_approvalResponse!.isCompleted) {
      _approvalResponse!.complete(false);
    }
    _approvalResponse = null;
    pendingApproval = null;
    status = LocalTaskStatus.stopped;
    _addStep('任务已停止', '不会继续执行；已完成的操作不会自动撤销。');
  }

  void decideApproval(bool allowed) {
    final response = _approvalResponse;
    if (response == null || response.isCompleted) return;
    response.complete(allowed);
    _approvalResponse = null;
    pendingApproval = null;
    if (!allowed) {
      _stopRequested = true;
      status = LocalTaskStatus.stopped;
      _addStep('任务已停止', '你拒绝了命令，本次任务不会继续。');
    } else if (!_stopRequested) {
      status = LocalTaskStatus.running;
    }
    notifyListeners();
  }

  Future<_ToolResult> _execute(AgentToolCall call) async {
    try {
      switch (call.name) {
        case 'observe_screen':
          final observation = await device.observe();
          _addStep('查看当前屏幕', '${observation.width} × ${observation.height}');
          return _ToolResult(
            output: {
              'ok': true,
              'width': observation.width,
              'height': observation.height,
              'nodes': observation.nodes,
              'screenshot': '截图将在下一条消息中提供',
            },
            observation: observation,
          );
        case 'tap_screen':
          final x = _coordinate(call.arguments, 'x');
          final y = _coordinate(call.arguments, 'y');
          await device.tap(x, y);
          _addStep('点击屏幕', '位置 $x, $y');
          return const _ToolResult(output: {'ok': true});
        case 'swipe_screen':
          final x1 = _coordinate(call.arguments, 'x1');
          final y1 = _coordinate(call.arguments, 'y1');
          final x2 = _coordinate(call.arguments, 'x2');
          final y2 = _coordinate(call.arguments, 'y2');
          final duration = call.arguments['durationMs'];
          if (duration is! int || duration < 100 || duration > 3000) {
            throw const FormatException('滑动时间须在 100 到 3000 毫秒之间');
          }
          await device.swipe(x1, y1, x2, y2, duration);
          _addStep('滑动屏幕', '$x1, $y1 → $x2, $y2');
          return const _ToolResult(output: {'ok': true});
        case 'type_text':
          final value = _string(call.arguments, 'text');
          await device.typeText(value);
          _addStep('输入文字', value);
          return const _ToolResult(output: {'ok': true});
        case 'press_back':
        case 'press_home':
          await device.globalAction(
            call.name == 'press_back' ? 'back' : 'home',
          );
          _addStep(call.name == 'press_back' ? '返回' : '回到桌面', '已完成');
          return const _ToolResult(output: {'ok': true});
        case 'run_command':
          final command = _string(call.arguments, 'command');
          final allowed = await _askApproval(command);
          if (!allowed) {
            _addStep('命令未执行', '你拒绝了这一步。');
            return const _ToolResult(
              output: {'ok': false, 'error': '用户拒绝执行命令'},
            );
          }
          if (_stopRequested) {
            return const _ToolResult(output: {'ok': false, 'error': '任务已停止'});
          }
          final result = await device.runCommand(command);
          _addStep(
            '运行命令',
            '退出码 ${result.exitCode}\n${_limit(result.stdout.isEmpty ? result.stderr : result.stdout, 600)}',
          );
          return _ToolResult(
            output: {
              'ok': result.exitCode == 0,
              'exitCode': result.exitCode,
              'stdout': _limit(result.stdout, 8000),
              'stderr': _limit(result.stderr, 4000),
            },
          );
        default:
          throw FormatException('不支持的操作：${call.name}');
      }
    } catch (failure) {
      final message = _readableError(failure);
      _addStep('操作失败', '${call.name}：$message');
      return _ToolResult(output: {'ok': false, 'error': message});
    }
  }

  Future<bool> _askApproval(String command) async {
    final response = Completer<bool>();
    _approvalResponse = response;
    pendingApproval = LocalTaskApproval(
      title: '运行 Termux 命令',
      detail: '工作目录：~/zhitide-workspace\n$command',
    );
    status = LocalTaskStatus.waitingApproval;
    notifyListeners();
    return response.future;
  }

  void _addStep(String title, String detail) {
    steps.add(LocalTaskStep(title: title, detail: detail));
    notifyListeners();
  }

  static int _coordinate(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is! int || value < 0 || value > 1000) {
      throw FormatException('$key 坐标须在 0 到 1000 之间');
    }
    return value;
  }

  static String _string(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key 不能为空');
    }
    return value;
  }

  static String _limit(String value, int length) =>
      value.length <= length ? value : '${value.substring(0, length)}\n…内容已截断';

  static String _readableError(Object failure) {
    if (failure is PlatformException) {
      switch (failure.code) {
        case 'accessibility_unavailable':
          return '手机操作权限未开启，请到系统设置中启用知汐。';
        case 'termux_unavailable':
          return '未找到 Termux，请先安装并打开它。';
        case 'termux_permission':
          return '请允许知汐在 Termux 中运行命令，并在 Termux 开启外部应用调用。';
        case 'termux_timeout':
          return 'Termux 命令等待超时，请检查 Termux 设置后重试。';
        default:
          return failure.message ?? '手机操作失败（${failure.code}）。';
      }
    }
    if (failure is StateError) return failure.message.toString();
    if (failure is FormatException) return failure.message;
    return failure.toString();
  }

  static const _systemPrompt =
      '''你是用户亲自启动的安卓本机任务助手，使用中文沟通。根据任务选择必要的工具：查询手机运行内存、存储空间、设备状态、代码或文件时，使用 Termux 的 run_command 读取实际数据和命令输出，不要截图；只有用户明确要操作其他应用的图形界面时，才使用 observe_screen 和界面操作工具。不要为了开始任务而预先截图。Termux 命令从 ~/zhitide-workspace 工作目录启动，可用来查看、修改代码与文件。只有用户明确要求的任务才可以执行。操作图形界面前先调用 observe_screen；每次界面变化后重新观察。截图坐标统一使用从 0 到 1000 的归一化坐标。不要猜测看不到的控件。运行命令前应用会逐条请求用户确认；如果用户拒绝，就不要换一种命令绕过。完成任务时说明实际完成的事，遇到权限或工具失败时说明原因，不要声称已经完成。''';

  static const _tools = <Map<String, dynamic>>[
    {
      'type': 'function',
      'function': {
        'name': 'observe_screen',
        'description': '仅在用户要求操作其他应用图形界面时读取当前手机屏幕截图和可访问控件；查询内存、存储、文件或代码时不要调用。',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'tap_screen',
        'description': '点击当前手机屏幕。x/y 是 0 到 1000 的归一化坐标。',
        'parameters': {
          'type': 'object',
          'properties': {
            'x': {'type': 'integer'},
            'y': {'type': 'integer'},
          },
          'required': ['x', 'y'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'swipe_screen',
        'description': '在手机屏幕滑动，坐标为 0 到 1000，时间为毫秒。',
        'parameters': {
          'type': 'object',
          'properties': {
            'x1': {'type': 'integer'},
            'y1': {'type': 'integer'},
            'x2': {'type': 'integer'},
            'y2': {'type': 'integer'},
            'durationMs': {'type': 'integer'},
          },
          'required': ['x1', 'y1', 'x2', 'y2', 'durationMs'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'type_text',
        'description': '用指定文字替换当前获得焦点的输入框内容。',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'press_back',
        'description': '执行安卓返回操作。',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'press_home',
        'description': '回到安卓桌面。',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_command',
        'description':
            '在 Termux 的 ~/zhitide-workspace 中运行一条 shell 命令。每次均需用户确认。可查询运行内存、存储、设备状态，也可读取或修改代码与文件。',
        'parameters': {
          'type': 'object',
          'properties': {
            'command': {'type': 'string'},
          },
          'required': ['command'],
        },
      },
    },
  ];
}

class _ToolResult {
  const _ToolResult({required this.output, this.observation});

  final Map<String, dynamic> output;
  final PhoneObservation? observation;
}

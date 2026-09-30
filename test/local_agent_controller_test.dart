import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhixi/agent_api.dart';
import 'package:zhixi/agent_device_bridge.dart';
import 'package:zhixi/api_key_store.dart';
import 'package:zhixi/chat_preferences.dart';
import 'package:zhixi/local_agent_controller.dart';

void main() {
  test('missing Termux permission stops before contacting the model', () async {
    final api = _FakeAgentApi([_commandTurn()]);
    final device = _FakeDevice()..termuxPermissionGranted = false;
    final controller = _controller(api, device);
    addTearDown(api.close);
    addTearDown(controller.dispose);

    await controller.startTask('检查项目');

    expect(controller.status, LocalTaskStatus.failed);
    expect(controller.error, contains('在 Termux 中运行命令'));
    expect(api.requests, isEmpty);
    expect(device.commands, isEmpty);
  });

  test(
    'Termux task runs without accessibility or a screen observation',
    () async {
      final api = _FakeAgentApi([_commandTurn(), _answerTurn()]);
      final device = _FakeDevice()..accessibilityEnabled = false;
      final controller = _controller(api, device);
      addTearDown(api.close);
      addTearDown(controller.dispose);

      final task = controller.startTask('在本地工作区检查项目');
      await _waitForStatus(controller, LocalTaskStatus.waitingApproval);
      expect(device.commands, isEmpty);

      controller.decideApproval(true);
      await task;

      expect(controller.status, LocalTaskStatus.completed);
      expect(device.commands, ['printf test']);
      expect(device.observations, 0);
      expect(api.requests, hasLength(2));
    },
  );

  test('a rejected command is never sent to Termux', () async {
    final api = _FakeAgentApi([_commandTurn(), _answerTurn()]);
    final device = _FakeDevice();
    final controller = _controller(api, device);
    addTearDown(api.close);
    addTearDown(controller.dispose);

    final task = controller.startTask('检查项目');
    await _waitForStatus(controller, LocalTaskStatus.waitingApproval);
    expect(controller.pendingApproval?.detail, contains('printf test'));

    controller.decideApproval(false);
    await task;

    expect(device.commands, isEmpty);
    expect(controller.status, LocalTaskStatus.stopped);
    expect(api.requests, hasLength(1));
  });

  test('an approved command runs once and returns its result', () async {
    final api = _FakeAgentApi([_commandTurn(), _answerTurn()]);
    final device = _FakeDevice();
    final controller = _controller(api, device);
    addTearDown(api.close);
    addTearDown(controller.dispose);

    final task = controller.startTask('检查项目');
    await _waitForStatus(controller, LocalTaskStatus.waitingApproval);
    expect(device.commands, isEmpty);

    controller.decideApproval(true);
    await task;

    expect(device.commands, ['printf test']);
    expect(controller.status, LocalTaskStatus.completed);
    final followUp = jsonDecode(api.requests.last) as List<dynamic>;
    final toolResult = followUp.last as Map<String, dynamic>;
    expect(jsonDecode(toolResult['content'] as String), {
      'ok': true,
      'exitCode': 0,
      'stdout': 'test',
      'stderr': '',
    });
  });

  test(
    'stopping during approval prevents the command and later turns',
    () async {
      final api = _FakeAgentApi([_commandTurn(), _answerTurn()]);
      final device = _FakeDevice();
      final controller = _controller(api, device);
      addTearDown(api.close);
      addTearDown(controller.dispose);

      final task = controller.startTask('检查项目');
      await _waitForStatus(controller, LocalTaskStatus.waitingApproval);

      controller.stop();
      await task;

      expect(controller.status, LocalTaskStatus.stopped);
      expect(controller.pendingApproval, isNull);
      expect(device.commands, isEmpty);
      expect(api.requests, hasLength(1));
    },
  );

  test(
    'selected task model is independent and stays Pro for commands',
    () async {
      final api = _FakeAgentApi([_commandTurn(), _answerTurn()]);
      final device = _FakeDevice();
      final preferences = _FakePreferencesStore();
      final controller = _controller(api, device, preferences);
      addTearDown(api.close);
      addTearDown(controller.dispose);

      await controller.selectTaskModel(DeepSeekModel.pro);
      expect(preferences.saved.model, DeepSeekModel.flash);
      expect(preferences.saved.taskModel, DeepSeekModel.pro);

      final task = controller.startTask('检查项目');
      await _waitForStatus(controller, LocalTaskStatus.waitingApproval);
      controller.decideApproval(true);
      await task;

      expect(api.models, [DeepSeekModel.pro.apiId, DeepSeekModel.pro.apiId]);
      expect(controller.activeModel, DeepSeekModel.pro);
    },
  );

  test('Pro screen observation sends the image to Flash only', () async {
    final api = _FakeAgentApi([_observeTurn(), _answerTurn()]);
    final device = _FakeDevice()..allowObservation = true;
    final preferences = _FakePreferencesStore();
    final controller = _controller(api, device, preferences);
    addTearDown(api.close);
    addTearDown(controller.dispose);

    await controller.selectTaskModel(DeepSeekModel.pro);
    await controller.startTask('查看屏幕');

    expect(controller.status, LocalTaskStatus.completed);
    expect(device.observations, 1);
    expect(api.models, [DeepSeekModel.pro.apiId, DeepSeekModel.flash.apiId]);
    final followUp = jsonDecode(api.requests.last) as List<dynamic>;
    final imageMessage = followUp.last as Map<String, dynamic>;
    final imageParts = imageMessage['content'] as List<dynamic>;
    expect(imageMessage['role'], 'user');
    expect((imageParts.last as Map<String, dynamic>)['type'], 'image_url');
    expect(preferences.saved.taskModel, DeepSeekModel.pro);
    expect(controller.taskModel, DeepSeekModel.pro);
    expect(controller.activeModel, DeepSeekModel.flash);
  });
}

LocalAgentController _controller(
  _FakeAgentApi api,
  _FakeDevice device, [
  _FakePreferencesStore? preferences,
]) {
  return LocalAgentController(
    api: api,
    device: device,
    keyStore: _FakeKeyStore(),
    prefsStore: preferences ?? _FakePreferencesStore(),
  );
}

Future<void> _waitForStatus(
  LocalAgentController controller,
  LocalTaskStatus expected,
) async {
  if (controller.status == expected) return;
  final reached = Completer<void>();
  void listener() {
    if (controller.status == expected && !reached.isCompleted) {
      reached.complete();
    }
  }

  controller.addListener(listener);
  try {
    await reached.future.timeout(const Duration(seconds: 2));
  } finally {
    controller.removeListener(listener);
  }
}

AgentTurn _commandTurn() => AgentTurn(
  assistantMessage: {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': 'call_1',
        'type': 'function',
        'function': {
          'name': 'run_command',
          'arguments': '{"command":"printf test"}',
        },
      },
    ],
  },
  content: null,
  reasoningContent: null,
  toolCalls: [
    AgentToolCall(
      id: 'call_1',
      name: 'run_command',
      arguments: {'command': 'printf test'},
    ),
  ],
);

AgentTurn _observeTurn() => AgentTurn(
  assistantMessage: {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': 'call_observe',
        'type': 'function',
        'function': {'name': 'observe_screen', 'arguments': '{}'},
      },
    ],
  },
  content: null,
  reasoningContent: null,
  toolCalls: [
    AgentToolCall(id: 'call_observe', name: 'observe_screen', arguments: {}),
  ],
);

AgentTurn _answerTurn() => const AgentTurn(
  assistantMessage: {'role': 'assistant', 'content': '检查完成。'},
  content: '检查完成。',
  reasoningContent: null,
  toolCalls: [],
);

class _FakeAgentApi extends AgentApi {
  _FakeAgentApi(this._turns);

  final List<AgentTurn> _turns;
  final List<String> requests = [];
  final List<String> models = [];

  @override
  Future<AgentTurn> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required bool thinkingEnabled,
  }) async {
    models.add(model);
    requests.add(jsonEncode(messages));
    return _turns[requests.length - 1];
  }
}

class _FakeDevice extends AgentDeviceBridge {
  final List<String> commands = [];
  bool accessibilityEnabled = true;
  bool termuxPermissionGranted = true;
  bool allowObservation = false;
  int observations = 0;

  @override
  Future<DeviceCapabilities> capabilities() async => DeviceCapabilities(
    accessibilityEnabled: accessibilityEnabled,
    termuxInstalled: true,
    termuxPermissionGranted: termuxPermissionGranted,
  );

  @override
  Future<PhoneObservation> observe() async {
    observations++;
    if (allowObservation) {
      return const PhoneObservation(
        screenshotBase64: 'aGVsbG8=',
        width: 100,
        height: 200,
        nodes: [],
      );
    }
    throw StateError('This Termux task must not observe the screen');
  }

  @override
  Future<PhoneCommandResult> runCommand(String command, {String? stdin}) async {
    commands.add(command);
    return const PhoneCommandResult(stdout: 'test', stderr: '', exitCode: 0);
  }
}

class _FakeKeyStore extends ApiKeyStore {
  @override
  Future<String?> read() async => 'sample-key';
}

class _FakePreferencesStore extends ChatPreferencesStore {
  ChatPreferences saved = const ChatPreferences();

  @override
  Future<ChatPreferences> read() async => saved;

  @override
  Future<void> write(ChatPreferences preferences) async {
    saved = preferences;
  }
}

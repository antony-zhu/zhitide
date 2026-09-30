import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhixi/agent_api.dart';
import 'package:zhixi/agent_device_bridge.dart';
import 'package:zhixi/api_key_store.dart';
import 'package:zhixi/chat_preferences.dart';
import 'package:zhixi/task_page.dart';

void main() {
  testWidgets('selected task model is sent and retained on reopening', (
    tester,
  ) async {
    final api = _FakeAgentApi((_) async => _finalTurn());
    final preferences = _FakePreferencesStore();
    final device = _FakeDevice();
    addTearDown(api.close);

    Widget page() => MaterialApp(
      home: TaskPage(
        api: api,
        device: device,
        keyStore: _FakeKeyStore(),
        prefsStore: preferences,
      ),
    );

    await tester.pumpWidget(page());
    await _waitForModelSelector(tester);
    expect(_visibleText(tester), contains('DeepSeek Flash'));

    await tester.tap(find.byKey(const Key('task_model_selector')));
    await tester.pumpAndSettle();
    final proItem = find.byWidgetPredicate(
      (widget) =>
          widget is CheckedPopupMenuItem<DeepSeekModel> &&
          widget.value == DeepSeekModel.pro,
    );
    await tester.ensureVisible(proItem);
    await tester.tap(proItem);
    await _pumpUntilCondition(
      tester,
      () => preferences.saved.taskModel == DeepSeekModel.pro,
    );

    expect(preferences.writes, 1);
    expect(preferences.saved.model, DeepSeekModel.flash);
    await tester.enterText(find.byType(TextField), '检查项目');
    await _waitForStartReady(tester);
    await tester.tap(find.text('开始任务'));
    await _pumpUntil(tester, find.byKey(const Key('task_reply')));
    expect(api.models, ['deepseek-v4-pro']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await _waitForModelSelector(tester);
    expect(_visibleText(tester), contains('DeepSeek V4 Pro'));
  });

  testWidgets('shows only the final reply after a command task', (
    tester,
  ) async {
    final finalResponse = Completer<AgentTurn>();
    final api = _FakeAgentApi(
      (call) => call == 1 ? Future.value(_commandTurn()) : finalResponse.future,
    );
    final device = _FakeDevice();
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(
          api: api,
          device: device,
          keyStore: _FakeKeyStore(),
          prefsStore: _FakePreferencesStore(),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'USER_INSTRUCTION_MARKER_81',
    );
    await _waitForStartReady(tester);
    await tester.tap(find.text('开始任务'));
    await _pumpUntil(tester, find.text('允许这一步'));

    expect(find.byKey(const Key('task_reply')), findsNothing);
    expect(_visibleText(tester), isNot(contains('USER_INSTRUCTION_MARKER_81')));
    expect(_visibleText(tester), isNot(contains('INTERIM_MODEL_MARKER_82')));
    expect(_visibleText(tester), contains('~/zhitide-workspace'));
    expect(_visibleText(tester), contains('printf CMD_MARKER_84'));
    expect(device.commands, isEmpty);

    await tester.tap(find.text('允许这一步'));
    await _pumpUntilCondition(tester, () => device.commands.isNotEmpty);
    await tester.pump();

    expect(device.commands, ['printf CMD_MARKER_84']);
    expect(find.byKey(const Key('task_reply')), findsNothing);
    expect(_visibleText(tester), isNot(contains('USER_INSTRUCTION_MARKER_81')));
    expect(_visibleText(tester), isNot(contains('INTERIM_MODEL_MARKER_82')));
    expect(_visibleText(tester), isNot(contains('TERMINAL_OUTPUT_MARKER_83')));
    expect(_visibleText(tester), isNot(contains('CMD_MARKER_84')));

    finalResponse.complete(_finalTurn());
    await _pumpUntil(tester, find.byKey(const Key('task_reply')));

    final reply = tester.widget<SelectableText>(
      find.byKey(const Key('task_reply')),
    );
    expect(reply.data, 'FINAL_ANSWER_MARKER_85');
    expect(_visibleText(tester), isNot(contains('USER_INSTRUCTION_MARKER_81')));
    expect(_visibleText(tester), isNot(contains('INTERIM_MODEL_MARKER_82')));
    expect(_visibleText(tester), isNot(contains('TERMINAL_OUTPUT_MARKER_83')));
    expect(_visibleText(tester), isNot(contains('CMD_MARKER_84')));
  });

  testWidgets('shows the failure as the terminal reply', (tester) async {
    final api = _FakeAgentApi((_) async {
      throw StateError('MODEL_FAILURE_MARKER_86');
    });
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(
          api: api,
          device: _FakeDevice(),
          keyStore: _FakeKeyStore(),
          prefsStore: _FakePreferencesStore(),
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'USER_INSTRUCTION_MARKER_81',
    );
    await _waitForStartReady(tester);
    await tester.tap(find.text('开始任务'));
    await _pumpUntil(tester, find.byKey(const Key('task_reply')));

    final reply = tester.widget<SelectableText>(
      find.byKey(const Key('task_reply')),
    );
    expect(reply.data, contains('MODEL_FAILURE_MARKER_86'));
    expect(reply.data, isNot(contains('USER_INSTRUCTION_MARKER_81')));
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) =>
    _pumpUntilCondition(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitForModelSelector(WidgetTester tester) =>
    _pumpUntilCondition(tester, () {
      final selector = find.byKey(const Key('task_model_selector'));
      if (selector.evaluate().isEmpty) return false;
      return tester.widget<PopupMenuButton<DeepSeekModel>>(selector).enabled;
    });

Future<void> _waitForStartReady(WidgetTester tester) =>
    _pumpUntilCondition(tester, () {
      final button = find.ancestor(
        of: find.text('开始任务'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      if (button.evaluate().isEmpty) return false;
      return tester.widget<FilledButton>(button).onPressed != null;
    });

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Expected task page state was not reached');
}

String _visibleText(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '');
  final selectable = tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map((widget) => widget.data ?? '');
  final editable = tester
      .widgetList<EditableText>(find.byType(EditableText))
      .map((widget) => widget.controller.text);
  return [...text, ...selectable, ...editable].join('\n');
}

AgentTurn _commandTurn() => AgentTurn(
  assistantMessage: {
    'role': 'assistant',
    'content': 'INTERIM_MODEL_MARKER_82',
    'tool_calls': [
      {
        'id': 'call_1',
        'type': 'function',
        'function': {
          'name': 'run_command',
          'arguments': '{"command":"printf CMD_MARKER_84"}',
        },
      },
    ],
  },
  content: 'INTERIM_MODEL_MARKER_82',
  reasoningContent: null,
  toolCalls: [
    AgentToolCall(
      id: 'call_1',
      name: 'run_command',
      arguments: {'command': 'printf CMD_MARKER_84'},
    ),
  ],
);

AgentTurn _finalTurn() => const AgentTurn(
  assistantMessage: {'role': 'assistant', 'content': 'FINAL_ANSWER_MARKER_85'},
  content: 'FINAL_ANSWER_MARKER_85',
  reasoningContent: null,
  toolCalls: [],
);

class _FakeAgentApi extends AgentApi {
  _FakeAgentApi(this._respond);

  final Future<AgentTurn> Function(int call) _respond;
  int calls = 0;
  final List<String> models = [];

  @override
  Future<AgentTurn> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required bool thinkingEnabled,
  }) {
    models.add(model);
    return _respond(++calls);
  }
}

class _FakeDevice extends AgentDeviceBridge {
  final List<String> commands = [];

  @override
  Future<DeviceCapabilities> capabilities() async => const DeviceCapabilities(
    accessibilityEnabled: false,
    termuxInstalled: true,
    termuxPermissionGranted: true,
  );

  @override
  Future<PhoneCommandResult> runCommand(String command, {String? stdin}) async {
    commands.add(command);
    return const PhoneCommandResult(
      stdout: 'TERMINAL_OUTPUT_MARKER_83',
      stderr: '',
      exitCode: 0,
    );
  }
}

class _FakeKeyStore extends ApiKeyStore {
  @override
  Future<String?> read() async => 'sample-key';
}

class _FakePreferencesStore extends ChatPreferencesStore {
  ChatPreferences saved = const ChatPreferences();
  int writes = 0;

  @override
  Future<ChatPreferences> read() async => saved;

  @override
  Future<void> write(ChatPreferences preferences) async {
    saved = preferences;
    writes++;
  }
}

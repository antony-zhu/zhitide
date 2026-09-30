import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zhixi/agent_api.dart';
import 'package:zhixi/deepseek_api.dart';

void main() {
  test(
    'sends screenshot and tools, then preserves a thinking tool call',
    () async {
      final assistantMessage = <String, dynamic>{
        'role': 'assistant',
        'content': null,
        'reasoning_content': '先查看手机界面。',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'tap', 'arguments': '{"x":120,"y":240}'},
          },
        ],
      };
      final tools = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': {
            'name': 'tap',
            'description': '点击屏幕',
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
      ];
      final messages = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '点击设置'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,cG5n'},
            },
          ],
        },
      ];
      final api = AgentApi(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://api.deepseek.com/chat/completions',
          );
          expect(request.headers['authorization'], 'Bearer sample-key');
          expect(request.headers['content-type'], contains('application/json'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'deepseek-flash');
          expect(body['messages'], messages);
          expect(body['tools'], tools);
          expect(body['thinking'], {'type': 'enabled'});
          expect(body['stream'], false);
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': assistantMessage},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);

      final turn = await api.complete(
        apiKey: 'sample-key',
        model: 'deepseek-flash',
        messages: messages,
        tools: tools,
        thinkingEnabled: true,
      );

      expect(turn.content, isNull);
      expect(turn.reasoningContent, '先查看手机界面。');
      expect(turn.assistantMessage, assistantMessage);
      expect(turn.toolCalls, hasLength(1));
      expect(turn.toolCalls.single.id, 'call_1');
      expect(turn.toolCalls.single.name, 'tap');
      expect(turn.toolCalls.single.arguments, {'x': 120, 'y': 240});
    },
  );

  test('sends pro model and returns a plain answer', () async {
    final api = AgentApi(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'deepseek-v4-pro');
        expect(body['thinking'], {'type': 'disabled'});
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '任务完成。'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);

    final turn = await api.complete(
      apiKey: 'sample-key',
      model: 'deepseek-v4-pro',
      messages: [
        {'role': 'user', 'content': '完成了吗？'},
      ],
      tools: [],
      thinkingEnabled: false,
    );

    expect(turn.content, '任务完成。');
    expect(turn.reasoningContent, isNull);
    expect(turn.toolCalls, isEmpty);
  });

  test('reports HTTP failures', () async {
    final api = AgentApi(
      client: MockClient((_) async => http.Response('', 401)),
    );
    addTearDown(api.close);

    await expectLater(
      api.complete(
        apiKey: 'bad-key',
        model: 'deepseek-flash',
        messages: [
          {'role': 'user', 'content': '你好'},
        ],
        tools: [],
        thinkingEnabled: false,
      ),
      throwsA(
        isA<DeepSeekApiException>().having(
          (error) => error.message,
          'message',
          contains('401'),
        ),
      ),
    );
  });

  test('rejects invalid tool arguments before execution', () async {
    final api = AgentApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {'name': 'tap', 'arguments': '{bad json'},
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(api.close);

    await expectLater(
      api.complete(
        apiKey: 'sample-key',
        model: 'deepseek-flash',
        messages: [
          {'role': 'user', 'content': '点击'},
        ],
        tools: [],
        thinkingEnabled: false,
      ),
      throwsA(
        isA<DeepSeekApiException>().having(
          (error) => error.message,
          'message',
          contains('工具参数格式有误'),
        ),
      ),
    );
  });
}

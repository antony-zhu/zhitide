import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zhixi/chat_message.dart';
import 'package:zhixi/deepseek_api.dart';

void main() {
  test('sends flash without thinking and returns the answer', () async {
    final api = DeepSeekApi(
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
        expect(body['thinking'], {'type': 'disabled'});
        expect(body['stream'], false);
        expect(body['messages'], [
          {'role': 'user', 'content': '你好'},
          {'role': 'assistant', 'content': '你好！'},
          {'role': 'user', 'content': '继续说'},
        ]);

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '好的。'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);

    final answer = await api.complete(
      apiKey: 'sample-key',
      model: 'deepseek-flash',
      thinkingEnabled: false,
      messages: [
        ChatMessage(role: ChatRole.user, content: '你好'),
        ChatMessage(role: ChatRole.assistant, content: '你好！'),
        ChatMessage(role: ChatRole.user, content: '继续说'),
      ],
    );

    expect(answer.content, '好的。');
    expect(answer.reasoningContent, isNull);
  });

  test('sends v4 pro with thinking and returns reasoning', () async {
    final api = DeepSeekApi(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], 'deepseek-v4-pro');
        expect(body['thinking'], {'type': 'enabled'});

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'reasoning_content': '  先分析问题。  ',
                  'content': '  这是回答。  ',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);

    final answer = await api.complete(
      apiKey: 'sample-key',
      model: 'deepseek-v4-pro',
      thinkingEnabled: true,
      messages: [ChatMessage(role: ChatRole.user, content: '你好')],
    );

    expect(answer.content, '这是回答。');
    expect(answer.reasoningContent, '先分析问题。');
  });

  for (final statusCode in [401, 503]) {
    test('reports HTTP $statusCode as a readable error', () async {
      final api = DeepSeekApi(
        client: MockClient(
          (_) async => http.Response(
            statusCode == 401
                ? jsonEncode({
                    'error': {'message': 'Authentication Fails'},
                  })
                : 'Service unavailable',
            statusCode,
          ),
        ),
      );
      addTearDown(api.close);

      await expectLater(
        api.complete(
          apiKey: 'sample-key',
          model: 'deepseek-flash',
          thinkingEnabled: false,
          messages: [ChatMessage(role: ChatRole.user, content: '你好')],
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('$statusCode'),
          ),
        ),
      );
    });
  }

  test('rejects unsupported model before sending', () async {
    var requestCount = 0;
    final api = DeepSeekApi(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('', 200);
      }),
    );
    addTearDown(api.close);

    await expectLater(
      api.complete(
        apiKey: 'sample-key',
        model: 'unsupported-model',
        thinkingEnabled: false,
        messages: [ChatMessage(role: ChatRole.user, content: '你好')],
      ),
      throwsArgumentError,
    );
    expect(requestCount, 0);
  });
}

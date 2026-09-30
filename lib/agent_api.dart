import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deepseek_api.dart';

class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class AgentTurn {
  const AgentTurn({
    required this.assistantMessage,
    required this.content,
    required this.reasoningContent,
    required this.toolCalls,
  });

  /// Keep this message intact when sending a tool result in the next request.
  final Map<String, dynamic> assistantMessage;
  final String? content;
  final String? reasoningContent;
  final List<AgentToolCall> toolCalls;
}

class AgentApi {
  AgentApi({http.Client? client}) : _client = client ?? http.Client();

  static final _endpoint = Uri.parse(
    'https://api.deepseek.com/chat/completions',
  );
  final http.Client _client;

  Future<AgentTurn> complete({
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required bool thinkingEnabled,
  }) async {
    if (model != 'deepseek-flash' && model != 'deepseek-v4-pro') {
      throw ArgumentError.value(model, 'model', '不支持的模型');
    }

    http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'tools': tools,
              'thinking': {'type': thinkingEnabled ? 'enabled' : 'disabled'},
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const DeepSeekApiException('请求超时，请稍后重试。');
    } on http.ClientException {
      throw const DeepSeekApiException('网络连接失败，请检查网络后重试。');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeepSeekApiException(_messageForStatus(response.statusCode));
    }

    Object? data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const DeepSeekApiException('服务返回了无法读取的内容，请稍后重试。');
    }

    if (data is! Map<String, dynamic>) {
      throw const DeepSeekApiException('服务返回的回复格式有误，请稍后重试。');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const DeepSeekApiException('服务返回的回复格式有误，请稍后重试。');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const DeepSeekApiException('服务返回的回复格式有误，请稍后重试。');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic> || message['role'] != 'assistant') {
      throw const DeepSeekApiException('服务返回的回复格式有误，请稍后重试。');
    }

    final rawContent = message['content'];
    final rawReasoning = message['reasoning_content'];
    if ((rawContent != null && rawContent is! String) ||
        (rawReasoning != null && rawReasoning is! String)) {
      throw const DeepSeekApiException('服务返回的回复格式有误，请稍后重试。');
    }
    final content = rawContent as String?;
    final reasoning = rawReasoning as String?;

    final rawCalls = message['tool_calls'];
    if (rawCalls != null && rawCalls is! List) {
      throw const DeepSeekApiException('服务返回的工具调用格式有误，请重试。');
    }
    final toolCalls = <AgentToolCall>[];
    if (rawCalls is List) {
      for (final rawCall in rawCalls) {
        if (rawCall is! Map<String, dynamic> ||
            rawCall['type'] != 'function' ||
            rawCall['id'] is! String ||
            (rawCall['id'] as String).isEmpty) {
          throw const DeepSeekApiException('服务返回的工具调用格式有误，请重试。');
        }
        final function = rawCall['function'];
        if (function is! Map<String, dynamic> ||
            function['name'] is! String ||
            (function['name'] as String).isEmpty ||
            function['arguments'] is! String) {
          throw const DeepSeekApiException('服务返回的工具调用格式有误，请重试。');
        }
        Object? arguments;
        try {
          arguments = jsonDecode(function['arguments'] as String);
        } on FormatException {
          throw const DeepSeekApiException('服务返回的工具参数格式有误，请重试。');
        }
        if (arguments is! Map<String, dynamic>) {
          throw const DeepSeekApiException('服务返回的工具参数格式有误，请重试。');
        }
        toolCalls.add(
          AgentToolCall(
            id: rawCall['id'] as String,
            name: function['name'] as String,
            arguments: arguments,
          ),
        );
      }
    }

    if ((content == null || content.trim().isEmpty) && toolCalls.isEmpty) {
      throw const DeepSeekApiException('服务未返回可显示的文字或工具调用，请稍后重试。');
    }
    return AgentTurn(
      assistantMessage: Map<String, dynamic>.from(message),
      content: content,
      reasoningContent: reasoning,
      toolCalls: toolCalls,
    );
  }

  void close() => _client.close();

  String _messageForStatus(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'API Key 无效（401），请前往设置检查。';
      case 402:
        return 'DeepSeek 账户余额不足（402），请检查账户。';
      case 429:
        return '请求过于频繁（429），请稍后重试。';
      case 500:
      case 503:
        return 'DeepSeek 服务暂时不可用（$statusCode），请稍后重试。';
      default:
        return '请求失败（$statusCode），请稍后重试。';
    }
  }
}

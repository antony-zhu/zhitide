import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_message.dart';

class DeepSeekApiException implements Exception {
  const DeepSeekApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeepSeekReply {
  const DeepSeekReply({required this.content, this.reasoningContent});

  final String content;
  final String? reasoningContent;
}

class DeepSeekApi {
  DeepSeekApi({http.Client? client}) : _client = client ?? http.Client();

  static final _endpoint = Uri.parse(
    'https://api.deepseek.com/chat/completions',
  );
  final http.Client _client;

  Future<DeepSeekReply> complete({
    required String apiKey,
    required List<ChatMessage> messages,
    required String model,
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
              'messages': [
                for (final message in messages)
                  {'role': message.role.name, 'content': message.content},
              ],
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

    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final message = first['message'];
          if (message is Map<String, dynamic>) {
            final content = message['content'];
            if (content is String && content.trim().isNotEmpty) {
              final reasoning = message['reasoning_content'];
              return DeepSeekReply(
                content: content.trim(),
                reasoningContent:
                    reasoning is String && reasoning.trim().isNotEmpty
                    ? reasoning.trim()
                    : null,
              );
            }
          }
        }
      }
    }
    throw const DeepSeekApiException('服务未返回可显示的文字，请稍后重试。');
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

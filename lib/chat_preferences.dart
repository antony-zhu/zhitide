import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum DeepSeekModel {
  flash('deepseek-flash', 'Flash'),
  pro('deepseek-v4-pro', 'V4 Pro');

  const DeepSeekModel(this.apiId, this.displayName);

  final String apiId;
  final String displayName;
}

class ChatPreferences {
  const ChatPreferences({
    this.model = DeepSeekModel.flash,
    this.taskModel = DeepSeekModel.flash,
    this.thinkingEnabled = false,
    this.showReasoning = true,
  });

  final DeepSeekModel model;
  final DeepSeekModel taskModel;
  final bool thinkingEnabled;
  final bool showReasoning;

  ChatPreferences copyWith({
    DeepSeekModel? model,
    DeepSeekModel? taskModel,
    bool? thinkingEnabled,
    bool? showReasoning,
  }) {
    return ChatPreferences(
      model: model ?? this.model,
      taskModel: taskModel ?? this.taskModel,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      showReasoning: showReasoning ?? this.showReasoning,
    );
  }
}

class ChatPreferencesStore {
  ChatPreferencesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'chat_preferences';
  final FlutterSecureStorage _storage;

  Future<ChatPreferences> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return const ChatPreferences();

    final saved = jsonDecode(value) as Map<String, dynamic>;
    return ChatPreferences(
      model: saved['model'] == DeepSeekModel.pro.apiId
          ? DeepSeekModel.pro
          : DeepSeekModel.flash,
      taskModel: saved['taskModel'] == DeepSeekModel.pro.apiId
          ? DeepSeekModel.pro
          : DeepSeekModel.flash,
      thinkingEnabled: saved['thinkingEnabled'] == true,
      showReasoning: saved['showReasoning'] != false,
    );
  }

  Future<void> write(ChatPreferences preferences) {
    return _storage.write(
      key: _key,
      value: jsonEncode({
        'model': preferences.model.apiId,
        'taskModel': preferences.taskModel.apiId,
        'thinkingEnabled': preferences.thinkingEnabled,
        'showReasoning': preferences.showReasoning,
      }),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import 'api_key_store.dart';
import 'chat_preferences.dart';

const _backgroundTop = Color(0xFF071A20);
const _backgroundBottom = Color(0xFF0C2A30);
const _glass = Color(0xC9163940);
const _card = Color(0xD117363D);
const _glassBorder = Color(0x2BFFFFFF);
const _primaryText = Color(0xFFF0FAF7);
const _secondaryText = Color(0xFFB6CCD0);
const _accent = Color(0xFF79E2D2);

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.keyStore,
    required this.prefsStore,
  });

  final ApiKeyStore keyStore;
  final ChatPreferencesStore prefsStore;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _keyController = TextEditingController();

  ChatPreferences _preferences = const ChatPreferences();
  bool _checkingKey = true;
  bool _loadingPreferences = true;
  bool _savingPreferences = false;
  bool _hasSavedKey = false;
  bool _savingKey = false;
  String? _keyError;
  String? _preferencesError;

  bool get _canSaveKey =>
      !_checkingKey &&
      !_savingKey &&
      !_savingPreferences &&
      _keyController.text.trim().isNotEmpty;

  bool get _canChangePreferences =>
      !_loadingPreferences && !_savingPreferences && !_savingKey;

  @override
  void initState() {
    super.initState();
    _checkSavedKey();
    _loadPreferences();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _checkSavedKey() async {
    try {
      final key = await widget.keyStore.read();
      if (!mounted) return;
      setState(() {
        _hasSavedKey = key?.isNotEmpty == true;
        _checkingKey = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingKey = false;
        _keyError = '无法读取已保存的密钥，你仍可输入新密钥并保存。';
      });
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await widget.prefsStore.read();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _loadingPreferences = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPreferences = false;
        _preferencesError = '无法读取模型设置，当前显示默认选项。';
      });
    }
  }

  Future<void> _savePreferences(ChatPreferences next) async {
    if (!_canChangePreferences) return;
    final previous = _preferences;
    setState(() {
      _preferences = next;
      _savingPreferences = true;
      _preferencesError = null;
    });

    try {
      await widget.prefsStore.write(next);
      if (!mounted) return;
      setState(() => _savingPreferences = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preferences = previous;
        _savingPreferences = false;
        _preferencesError = '模型设置保存失败，请重试。';
      });
    }
  }

  Future<void> _saveKey() async {
    if (!_canSaveKey) return;
    setState(() {
      _savingKey = true;
      _keyError = null;
    });

    try {
      await widget.keyStore.write(_keyController.text.trim());
      if (!mounted) return;
      _keyController.clear();
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingKey = false;
        _keyError = '密钥保存失败，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_savingPreferences && !_savingKey,
      child: Scaffold(
        backgroundColor: _backgroundTop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_backgroundTop, _backgroundBottom],
                ),
              ),
            ),
            Positioned(
              top: -110,
              right: -140,
              child: IgnorePointer(
                child: Container(
                  width: 390,
                  height: 390,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x5C237C7D), Color(0x00237C7D)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -170,
              left: -150,
              child: IgnorePointer(
                child: Container(
                  width: 390,
                  height: 390,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x42305972), Color(0x00305972)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildServiceCard(),
                          const SizedBox(height: 26),
                          _sectionHeading('选择模型'),
                          const SizedBox(height: 12),
                          _buildModelOption(DeepSeekModel.flash),
                          const SizedBox(height: 10),
                          _buildModelOption(DeepSeekModel.pro),
                          const SizedBox(height: 26),
                          _sectionHeading('能力选项'),
                          const SizedBox(height: 12),
                          _glassCard(
                            child: Column(
                              children: [
                                _buildSwitchRow(
                                  title: '深度思考',
                                  description: '让模型在回答前进行更充分的推理',
                                  value: _preferences.thinkingEnabled,
                                  onChanged: _canChangePreferences
                                      ? (value) => _savePreferences(
                                          _preferences.copyWith(
                                            thinkingEnabled: value,
                                          ),
                                        )
                                      : null,
                                ),
                                const Divider(height: 1, color: _glassBorder),
                                _buildSwitchRow(
                                  title: '显示思考过程',
                                  description: '控制已有和之后的思考内容展示',
                                  value: _preferences.showReasoning,
                                  onChanged: _canChangePreferences
                                      ? (value) => _savePreferences(
                                          _preferences.copyWith(
                                            showReasoning: value,
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildNetworkCard(),
                          if (_preferencesError != null) ...[
                            const SizedBox(height: 12),
                            _errorText(_preferencesError!),
                          ],
                          const SizedBox(height: 26),
                          _sectionHeading('DeepSeek API Key'),
                          const SizedBox(height: 12),
                          _buildKeyCard(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: _glass,
            border: Border(bottom: BorderSide(color: _glassBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 20, 11),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回聊天',
                onPressed: _savingPreferences || _savingKey
                    ? null
                    : () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  foregroundColor: _primaryText,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模型设置',
                    style: TextStyle(
                      color: _primaryText,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '调整知汐的回答方式',
                    style: TextStyle(color: _secondaryText, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _glassBorder),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000609),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeading(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _primaryText,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildServiceCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2D878B), Color(0xFF164249)],
                ),
                border: Border.all(color: const Color(0x6BB8FFF0)),
              ),
              child: const Icon(Icons.waves_rounded, color: _primaryText),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前服务',
                    style: TextStyle(color: _secondaryText, fontSize: 12),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'DeepSeek',
                    style: TextStyle(
                      color: _primaryText,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelOption(DeepSeekModel model) {
    final selected = _preferences.model == model;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? const Color(0xD7205359) : _card,
          border: Border.all(
            color: selected ? const Color(0xB379E2D2) : _glassBorder,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000609),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _canChangePreferences && !selected
              ? () => _savePreferences(_preferences.copyWith(model: model))
              : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DeepSeek ${model.displayName}',
                        style: const TextStyle(
                          color: _primaryText,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        model.apiId,
                        style: const TextStyle(
                          color: _secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? _accent : _secondaryText,
                  size: 23,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final disabled = onChanged == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: disabled ? _secondaryText : _primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _accent,
            activeTrackColor: const Color(0xFF236B6A),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard() {
    return _glassCard(
      child: const Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_off_rounded, color: _secondaryText, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '联网搜索 · 暂不可用',
                    style: TextStyle(
                      color: _primaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'DeepSeek API 暂不支持模型内置联网搜索。',
                    style: TextStyle(
                      color: _secondaryText,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard() {
    return _glassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _keyController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              cursorColor: _accent,
              style: const TextStyle(color: _primaryText, fontSize: 16),
              onChanged: (_) => setState(() => _keyError = null),
              onSubmitted: (_) => _saveKey(),
              decoration: InputDecoration(
                hintText: _hasSavedKey ? '••••••••••••' : '输入 DeepSeek API Key',
                hintStyle: const TextStyle(color: _secondaryText),
                filled: true,
                fillColor: const Color(0xD70C2B32),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: _glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: _accent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _checkingKey
                  ? '正在读取密钥状态…'
                  : _hasSavedKey
                  ? '已保存 API Key，输入新密钥可替换。'
                  : '尚未保存 API Key。',
              style: const TextStyle(
                color: _secondaryText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '密钥保存在本机，并仅用于请求 DeepSeek 接口。',
              style: TextStyle(
                color: _secondaryText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (_keyError != null) ...[
              const SizedBox(height: 12),
              _errorText(_keyError!),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _canSaveKey ? _saveKey : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF073036),
                disabledBackgroundColor: const Color(0xFF36565B),
                disabledForegroundColor: _secondaryText,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(_savingKey ? '正在保存…' : '保存密钥'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorText(String message) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFFFC7C2),
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}

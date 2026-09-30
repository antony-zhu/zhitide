import 'dart:ui';

import 'package:flutter/material.dart';

import 'api_key_store.dart';
import 'chat_message.dart';
import 'chat_preferences.dart';
import 'deepseek_api.dart';
import 'settings_page.dart';

const _backgroundTop = Color(0xFF071A20);
const _backgroundBottom = Color(0xFF0C2A30);
const _glass = Color(0xC9163940);
const _glassBorder = Color(0x2BFFFFFF);
const _primaryText = Color(0xFFF0FAF7);
const _secondaryText = Color(0xFFB6CCD0);
const _accent = Color(0xFF79E2D2);

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.api,
    required this.keyStore,
    required this.prefsStore,
  });

  final DeepSeekApi api;
  final ApiKeyStore keyStore;
  final ChatPreferencesStore prefsStore;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messages = <ChatMessage>[];
  final _collapsedReasoning = <ChatMessage>{};
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

  ChatPreferences _preferences = const ChatPreferences();
  String? _apiKey;
  String? _keyError;
  String? _preferencesError;
  String? _sendError;
  bool _loadingKey = true;
  bool _loadingPreferences = true;
  bool _sending = false;

  bool get _canSend =>
      !_loadingKey &&
      !_loadingPreferences &&
      !_sending &&
      _apiKey != null &&
      _composer.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await Future.wait([_loadKey(), _loadPreferences()]);
  }

  Future<void> _loadKey() async {
    setState(() {
      _loadingKey = true;
      _keyError = null;
    });
    try {
      final key = (await widget.keyStore.read())?.trim();
      if (!mounted) return;
      setState(() {
        _apiKey = key?.isNotEmpty == true ? key : null;
        _loadingKey = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiKey = null;
        _loadingKey = false;
        _keyError = '无法读取本机保存的密钥，请在设置中重新保存。';
      });
    }
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _loadingPreferences = true;
      _preferencesError = null;
    });
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
        _preferences = const ChatPreferences();
        _loadingPreferences = false;
        _preferencesError = '无法读取模型设置，已使用默认选项。';
      });
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          keyStore: widget.keyStore,
          prefsStore: widget.prefsStore,
        ),
      ),
    );
    if (!mounted) return;
    await _loadSettings();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final draft = _composer.text;
    final key = _apiKey!;
    final preferences = _preferences;
    final outgoing = ChatMessage(role: ChatRole.user, content: draft.trim());
    setState(() {
      _messages.add(outgoing);
      _composer.clear();
      _sending = true;
      _sendError = null;
    });
    _scrollToBottom();

    try {
      final reply = await widget.api.complete(
        apiKey: key,
        messages: List<ChatMessage>.unmodifiable(_messages),
        model: preferences.model.apiId,
        thinkingEnabled: preferences.thinkingEnabled,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: reply.content,
            reasoningContent: reply.reasoningContent,
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    } on DeepSeekApiException catch (error) {
      _handleSendFailure(outgoing, draft, error.message);
    } catch (_) {
      _handleSendFailure(outgoing, draft, '发送失败，请检查网络和 API Key 后重试。');
    }
  }

  void _handleSendFailure(ChatMessage outgoing, String draft, String message) {
    if (!mounted) return;
    setState(() {
      _messages.remove(outgoing);
      _composer.text = draft;
      _sending = false;
      _sendError = message;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final end = _scrollController.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(end);
      } else {
        _scrollController.animateTo(
          end,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                if (_keyError != null && _messages.isNotEmpty)
                  _buildErrorNotice(_keyError!),
                if (_preferencesError != null && _messages.isNotEmpty)
                  _buildErrorNotice(_preferencesError!),
                Expanded(child: _buildConversation()),
                _buildComposer(),
              ],
            ),
          ),
        ],
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
          padding: const EdgeInsets.fromLTRB(20, 11, 12, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '知汐',
                      style: TextStyle(
                        color: _primaryText,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _loadingPreferences
                          ? '正在读取模型…'
                          : 'DeepSeek · ${_preferences.model.displayName}',
                      style: const TextStyle(
                        color: _secondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '模型设置',
                onPressed: _loadingKey || _loadingPreferences
                    ? null
                    : _openSettings,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x2AFFFFFF),
                  foregroundColor: _primaryText,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversation() {
    if (_messages.isEmpty && !_sending) {
      return Column(
        children: [
          Expanded(child: Center(child: _buildEmptyState())),
          if (_sendError != null) _buildErrorNotice(_sendError!),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      itemCount:
          _messages.length + (_sending ? 1 : 0) + (_sendError == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index < _messages.length) {
          return _buildMessage(_messages[index]);
        }
        if (_sending) return _buildLoadingMessage();
        return _buildErrorNotice(_sendError!);
      },
    );
  }

  Widget _buildEmptyState() {
    final String title;
    if (_loadingKey || _loadingPreferences) {
      title = '正在读取设置…';
    } else if (_keyError != null) {
      title = _keyError!;
    } else if (_apiKey == null) {
      title = '添加 DeepSeek API Key 后即可聊天';
    } else {
      title = '想聊些什么？';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2D878B), Color(0xFF164249)],
              ),
              border: Border.all(color: const Color(0x6BB8FFF0)),
              boxShadow: const [
                BoxShadow(color: Color(0x5535C6B7), blurRadius: 44),
              ],
            ),
            child: const Icon(
              Icons.waves_rounded,
              color: _primaryText,
              size: 36,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _apiKey == null ? 18 : 25,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: _primaryText,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'DeepSeek ${_preferences.model.displayName} · '
            '${_preferences.thinkingEnabled ? '深度思考已开启' : '深度思考未开启'}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _secondaryText,
            ),
          ),
          if (!_loadingKey && !_loadingPreferences && _apiKey == null) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _openSettings,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: Color(0x8879E2D2)),
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: const Text('前往模型设置'),
            ),
          ],
          if (_preferencesError != null) ...[
            const SizedBox(height: 20),
            Text(
              _preferencesError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFC7C2), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.role == ChatRole.user;
    final showReasoning =
        !isUser &&
        _preferences.showReasoning &&
        message.reasoningContent?.isNotEmpty == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF1C6D71) : const Color(0xDD17363D),
              border: Border.all(
                color: isUser
                    ? const Color(0x6628B6AD)
                    : const Color(0x2BFFFFFF),
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 20),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x25000609),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showReasoning) ...[
                  _buildReasoning(message),
                  const SizedBox(height: 12),
                ],
                Semantics(
                  label: '${isUser ? '你' : '知汐'}：${message.content}',
                  child: ExcludeSemantics(
                    child: Text(
                      message.content,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: _primaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReasoning(ChatMessage message) {
    final collapsed = _collapsedReasoning.contains(message);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xB20D2730),
        border: Border.all(color: const Color(0x334DBDB2)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () {
                setState(() {
                  if (collapsed) {
                    _collapsedReasoning.remove(message);
                  } else {
                    _collapsedReasoning.add(message);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 15,
                      color: _accent,
                    ),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        '思考过程',
                        style: TextStyle(
                          color: _secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 19,
                      color: _secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text(
                      message.reasoningContent!,
                      style: const TextStyle(
                        color: _secondaryText,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingMessage() {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xDD17363D),
            border: Border.all(color: _glassBorder),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!reducedMotion) ...[
                const ExcludeSemantics(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Semantics(
                liveRegion: true,
                child: const Text(
                  '知汐正在回复…',
                  style: TextStyle(fontSize: 14, color: _secondaryText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorNotice(String message) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xD14D2227),
          border: Border.all(color: const Color(0x66FFA8A0)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: Color(0xFFFFC7C2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFFFFE1DD),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: _glass,
            border: Border(top: BorderSide(color: _glassBorder)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _composer,
                  readOnly: _sending,
                  onChanged: (_) => setState(() => _sendError = null),
                  onTap: _scrollToBottom,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  cursorColor: _accent,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: _primaryText,
                  ),
                  decoration: InputDecoration(
                    hintText: '给知汐发消息',
                    hintStyle: const TextStyle(color: _secondaryText),
                    filled: true,
                    fillColor: const Color(0xD70C2B32),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(23),
                      borderSide: const BorderSide(color: _glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(23),
                      borderSide: const BorderSide(color: _accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSend ? _send : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: const Color(0xFF073036),
                  disabledBackgroundColor: const Color(0xFF36565B),
                  disabledForegroundColor: _secondaryText,
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  semanticLabel: '发送消息',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'agent_api.dart';
import 'agent_device_bridge.dart';
import 'api_key_store.dart';
import 'chat_preferences.dart';
import 'local_agent_controller.dart';

const _backgroundTop = Color(0xFF071A20);
const _backgroundBottom = Color(0xFF0C2A30);
const _glass = Color(0xC9163940);
const _card = Color(0xE017363D);
const _border = Color(0x2BFFFFFF);
const _text = Color(0xFFF0FAF7);
const _muted = Color(0xFFB6CCD0);
const _accent = Color(0xFF79E2D2);
const _warning = Color(0xFFFFC7A2);
const _error = Color(0xFFFFC7C2);

class TaskPage extends StatefulWidget {
  const TaskPage({
    super.key,
    required this.api,
    required this.device,
    required this.keyStore,
    required this.prefsStore,
  });

  final AgentApi api;
  final AgentDeviceBridge device;
  final ApiKeyStore keyStore;
  final ChatPreferencesStore prefsStore;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> with WidgetsBindingObserver {
  late final LocalAgentController _controller;
  final _instruction = TextEditingController();
  final _scroll = ScrollController();
  String? _setupActionError;
  String? _modelError;
  bool _loadingTaskModel = true;
  bool _savingTaskModel = false;

  bool get _ready {
    final capabilities = _controller.capabilities;
    return capabilities?.termuxInstalled == true &&
        capabilities?.termuxPermissionGranted == true;
  }

  bool get _canStart =>
      !_controller.isActive &&
      !_loadingTaskModel &&
      !_savingTaskModel &&
      _ready &&
      _instruction.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = LocalAgentController(
      api: widget.api,
      device: widget.device,
      keyStore: widget.keyStore,
      prefsStore: widget.prefsStore,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.refreshCapabilities());
    unawaited(_refreshTaskModel());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.stop();
    _controller.dispose();
    _instruction.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshCapabilities());
      unawaited(_refreshTaskModel());
    }
  }

  Future<void> _refreshTaskModel() async {
    setState(() => _loadingTaskModel = true);
    try {
      await _controller.refreshTaskModel();
      if (!mounted) return;
      setState(() {
        _loadingTaskModel = false;
        _modelError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTaskModel = false;
        _modelError = '无法读取本机任务模型设置。';
      });
    }
  }

  Future<void> _selectTaskModel(DeepSeekModel model) async {
    if (_controller.isActive || _loadingTaskModel || _savingTaskModel) return;
    if (model == _controller.taskModel) return;
    setState(() {
      _savingTaskModel = true;
      _modelError = null;
    });
    try {
      await _controller.selectTaskModel(model);
    } catch (_) {
      if (!mounted) return;
      setState(() => _modelError = '本机任务模型保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _savingTaskModel = false);
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      setState(() => _setupActionError = null);
      await _controller.device.openAccessibilitySettings();
    } catch (_) {
      if (mounted) {
        setState(() => _setupActionError = '无法打开系统设置，请手动找到知汐的无障碍服务。');
      }
    }
  }

  Future<void> _openTermux() async {
    try {
      setState(() => _setupActionError = null);
      await _controller.device.openTermux();
    } catch (_) {
      if (mounted) {
        setState(() => _setupActionError = '无法打开 Termux，请确认它已安装。');
      }
    }
  }

  Future<void> _requestTermuxPermission() async {
    try {
      setState(() => _setupActionError = null);
      await _controller.device.requestTermuxPermission();
      await _controller.refreshCapabilities();
    } catch (_) {
      if (mounted) {
        setState(
          () => _setupActionError = '无法请求 Termux 运行命令权限，请在手机设置中检查知汐的应用权限。',
        );
      }
    }
  }

  void _start() {
    if (!_canStart) return;
    final task = _instruction.text.trim();
    FocusScope.of(context).unfocus();
    _instruction.clear();
    setState(() {});
    unawaited(_controller.startTask(task));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
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
                  Expanded(child: _buildContent()),
                  _buildBottomPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final displayedModel = _controller.status == LocalTaskStatus.idle
        ? _controller.taskModel
        : _controller.activeModel;
    final canSelectModel =
        !_controller.isActive && !_loadingTaskModel && !_savingTaskModel;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: _glass,
            border: Border(bottom: BorderSide(color: _border)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 11, 12, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '本机任务',
                      style: TextStyle(
                        color: _text,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor(_controller.status),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: PopupMenuButton<DeepSeekModel>(
                              key: const Key('task_model_selector'),
                              tooltip: '选择本机任务模型',
                              enabled: canSelectModel,
                              position: PopupMenuPosition.under,
                              padding: EdgeInsets.zero,
                              onSelected: (model) =>
                                  unawaited(_selectTaskModel(model)),
                              itemBuilder: (context) => [
                                for (final model in DeepSeekModel.values)
                                  CheckedPopupMenuItem<DeepSeekModel>(
                                    value: model,
                                    checked: model == _controller.taskModel,
                                    child: Text(
                                      'DeepSeek ${model.displayName}',
                                    ),
                                  ),
                              ],
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _controller.isActive
                                          ? 'DeepSeek ${displayedModel.displayName}'
                                          : 'DeepSeek ${displayedModel.displayName} · ${_statusLabel(_controller.status)}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (canSelectModel) ...[
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: _muted,
                                      size: 16,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_modelError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _modelError!,
                        style: const TextStyle(
                          color: _error,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_controller.isActive)
                OutlinedButton.icon(
                  onPressed: _controller.stop,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('停止'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _error,
                    side: const BorderSide(color: Color(0x88FFC7C2)),
                    minimumSize: const Size(82, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.phone_android_rounded, color: _accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final capabilities = _controller.capabilities;
    final isIdle = _controller.status == LocalTaskStatus.idle;
    if (_controller.isActive) return const SizedBox.expand();

    if (isIdle &&
        capabilities != null &&
        _ready &&
        capabilities.accessibilityEnabled &&
        _controller.setupError == null &&
        _setupActionError == null) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: _buildEmptyState()),
          ),
        ),
      );
    }
    return ListView(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      children: [
        if (isIdle && capabilities == null && _controller.setupError == null)
          _buildSetupLoading()
        else if (isIdle && capabilities == null)
          _surface(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton.icon(
                onPressed: () => unawaited(_controller.refreshCapabilities()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新检查本机能力'),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            ),
          )
        else if (isIdle &&
            capabilities != null &&
            (!_ready || !capabilities.accessibilityEnabled)) ...[
          _buildSetupCard(capabilities),
          const SizedBox(height: 16),
        ],
        if (isIdle && _controller.setupError != null)
          _buildNotice(_controller.setupError!, isError: true),
        if (isIdle && _setupActionError != null)
          _buildNotice(_setupActionError!, isError: true),
        if (isIdle) _buildEmptyState() else _buildFinalReply(),
      ],
    );
  }

  Widget _buildSetupLoading() {
    return _surface(
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
            SizedBox(width: 12),
            Text('正在检查本机权限…', style: TextStyle(color: _muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupCard(DeviceCapabilities capabilities) {
    return _surface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本机能力',
              style: TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildSetupRow(
              icon: Icons.terminal_rounded,
              title: 'Termux',
              description: capabilities.termuxInstalled
                  ? '本机内存、存储信息和工作区文件、代码、命令均由 Termux 处理'
                  : '请先安装并打开 Termux，再返回这里检查',
              ready: capabilities.termuxInstalled,
              actionLabel: capabilities.termuxInstalled ? '打开' : null,
              action: capabilities.termuxInstalled ? _openTermux : null,
            ),
            if (capabilities.termuxInstalled) ...[
              const Divider(height: 20, color: _border),
              _buildSetupRow(
                icon: Icons.key_rounded,
                title: '运行命令权限',
                description: capabilities.termuxPermissionGranted
                    ? '已允许知汐调用 Termux'
                    : '点“去授权”，在系统弹窗中允许知汐调用 Termux',
                ready: capabilities.termuxPermissionGranted,
                actionLabel: '去授权',
                action: _requestTermuxPermission,
              ),
            ],
            const Divider(height: 20, color: _border),
            _buildSetupRow(
              icon: Icons.touch_app_rounded,
              title: '操作其他 App · 可选',
              description: capabilities.accessibilityEnabled
                  ? '手机操作权限已开启；界面操作需要读取屏幕截图'
                  : '只有让知汐操作其他 App 界面时才需开启无障碍；纯 Termux 任务无需截图',
              ready: capabilities.accessibilityEnabled,
              actionLabel: capabilities.accessibilityEnabled ? null : '去开启',
              action: capabilities.accessibilityEnabled
                  ? null
                  : _openAccessibilitySettings,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => unawaited(_controller.refreshCapabilities()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新检查'),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupRow({
    required IconData icon,
    required String title,
    required String description,
    required bool ready,
    required String? actionLabel,
    required VoidCallback? action,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0x54205A60),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _accent, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (ready)
          const Icon(Icons.check_circle_rounded, color: _accent, size: 23),
        if (actionLabel != null)
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
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
              Icons.auto_awesome_rounded,
              color: _text,
              size: 35,
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            '把想做的事交给知汐',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: 23,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalReply() {
    final status = _controller.status;
    final title = switch (status) {
      LocalTaskStatus.completed => '知汐',
      LocalTaskStatus.stopped => '任务已停止',
      _ => '任务未完成',
    };
    final color = status == LocalTaskStatus.completed ? _accent : _error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == LocalTaskStatus.completed
                    ? Icons.auto_awesome_rounded
                    : Icons.info_outline_rounded,
                color: color,
                size: 21,
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  color: _text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Semantics(
            liveRegion: true,
            child: SelectableText(
              _finalReplyText(),
              key: const Key('task_reply'),
              style: const TextStyle(color: _text, fontSize: 16, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  String _finalReplyText() {
    switch (_controller.status) {
      case LocalTaskStatus.completed:
        for (final step in _controller.steps.reversed) {
          if (step.title == '任务回复' && step.detail.trim().isNotEmpty) {
            return step.detail.trim();
          }
        }
        return '任务已完成。';
      case LocalTaskStatus.failed:
        return _controller.error?.trim().isNotEmpty == true
            ? _controller.error!.trim()
            : '任务未完成，请重试。';
      case LocalTaskStatus.stopped:
        for (final step in _controller.steps.reversed) {
          if (step.title == '任务已停止' && step.detail.trim().isNotEmpty) {
            return step.detail.trim();
          }
        }
        return '任务已停止。';
      case LocalTaskStatus.idle:
      case LocalTaskStatus.running:
      case LocalTaskStatus.waitingApproval:
        return '';
    }
  }

  Widget _buildBottomPanel() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: _glass,
            border: Border(top: BorderSide(color: _border)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_controller.pendingApproval != null)
                _buildApproval(_controller.pendingApproval!)
              else if (_controller.isActive)
                _buildRunningFooter()
              else
                _buildTaskComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApproval(LocalTaskApproval approval) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xF01B383E),
        border: Border.all(color: const Color(0x8879E2D2)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: _warning, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  '等待你确认',
                  style: TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${approval.title} · 可能读取或修改本机文件',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 11),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.30,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xEE09252C),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  approval.detail,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 12,
                    height: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _controller.decideApproval(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _border),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _controller.decideApproval(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF073036),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('允许这一步'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRunningFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          if (!MediaQuery.disableAnimationsOf(context)) ...[
            const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
            const SizedBox(width: 11),
          ],
          const Expanded(
            child: Text(
              '正在处理…',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskComposer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _instruction,
          onChanged: (_) => setState(() {}),
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          cursorColor: _accent,
          style: const TextStyle(color: _text, fontSize: 15, height: 1.4),
          decoration: InputDecoration(
            hintText: '描述想让知汐在手机上完成的事…',
            hintStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: const Color(0xD70C2B32),
            contentPadding: const EdgeInsets.all(14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _accent),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _canStart ? _start : null,
          icon: const Icon(Icons.arrow_forward_rounded, size: 19),
          label: const Text('开始任务'),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xFF073036),
            disabledBackgroundColor: const Color(0xFF36565B),
            disabledForegroundColor: _muted,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotice(String message, {required bool isError}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isError ? const Color(0xD14D2227) : const Color(0xD117363D),
            border: Border.all(
              color: isError ? const Color(0x66FFA8A0) : _border,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: isError ? _error : _muted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _surface({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
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

  String _statusLabel(LocalTaskStatus status) => switch (status) {
    LocalTaskStatus.idle => '待开始',
    LocalTaskStatus.running => '执行中',
    LocalTaskStatus.waitingApproval => '等待确认',
    LocalTaskStatus.completed => '已完成',
    LocalTaskStatus.stopped => '已停止',
    LocalTaskStatus.failed => '未完成',
  };

  Color _statusColor(LocalTaskStatus status) => switch (status) {
    LocalTaskStatus.waitingApproval => _warning,
    LocalTaskStatus.failed || LocalTaskStatus.stopped => _error,
    _ => _accent,
  };
}

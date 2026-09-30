import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'agent_api.dart';
import 'agent_device_bridge.dart';
import 'api_key_store.dart';
import 'chat_page.dart';
import 'chat_preferences.dart';
import 'deepseek_api.dart';
import 'task_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZhixiApp());
}

class ZhixiApp extends StatefulWidget {
  const ZhixiApp({super.key});

  @override
  State<ZhixiApp> createState() => _ZhixiAppState();
}

class _ZhixiAppState extends State<ZhixiApp> {
  final DeepSeekApi _api = DeepSeekApi();
  final AgentApi _agentApi = AgentApi();
  final ApiKeyStore _keyStore = ApiKeyStore();
  final ChatPreferencesStore _prefsStore = ChatPreferencesStore();

  @override
  void dispose() {
    _api.close();
    _agentApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '知汐',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF79E2D2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF071A20),
      ),
      home: _HomeShell(
        chatApi: _api,
        agentApi: _agentApi,
        keyStore: _keyStore,
        prefsStore: _prefsStore,
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.chatApi,
    required this.agentApi,
    required this.keyStore,
    required this.prefsStore,
  });

  final DeepSeekApi chatApi;
  final AgentApi agentApi;
  final ApiKeyStore keyStore;
  final ChatPreferencesStore prefsStore;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _selectedPage = 0;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: const Color(0xFF071A20),
      body: IndexedStack(
        index: _selectedPage,
        children: [
          ChatPage(
            api: widget.chatApi,
            keyStore: widget.keyStore,
            prefsStore: widget.prefsStore,
          ),
          TaskPage(
            api: widget.agentApi,
            device: const AgentDeviceBridge(),
            keyStore: widget.keyStore,
            prefsStore: widget.prefsStore,
          ),
        ],
      ),
      bottomNavigationBar: keyboardVisible
          ? null
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: NavigationBar(
                  backgroundColor: const Color(0xDF102E35),
                  indicatorColor: const Color(0x3B79E2D2),
                  selectedIndex: _selectedPage,
                  onDestinationSelected: (index) {
                    setState(() => _selectedPage = index);
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.chat_bubble_outline_rounded),
                      selectedIcon: Icon(Icons.chat_bubble_rounded),
                      label: '聊天',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_awesome_motion_outlined),
                      selectedIcon: Icon(Icons.auto_awesome_motion_rounded),
                      label: '本机任务',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

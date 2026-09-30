import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api_key_store.dart';
import 'chat_page.dart';
import 'chat_preferences.dart';
import 'deepseek_api.dart';

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
  final ApiKeyStore _keyStore = ApiKeyStore();
  final ChatPreferencesStore _prefsStore = ChatPreferencesStore();

  @override
  void dispose() {
    _api.close();
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
      home: ChatPage(api: _api, keyStore: _keyStore, prefsStore: _prefsStore),
    );
  }
}

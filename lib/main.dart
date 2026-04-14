import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'config/theme.dart';
import 'services/database_service.dart';
import 'services/translation_service.dart';
import 'services/cefr_service.dart';
import 'services/srs_service.dart';
import 'providers/settings_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/srs_provider.dart';
import 'providers/lesson_provider.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure window
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: 'Zaban — AI English Tutor',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Initialize core services (backend-agnostic)
  final db = DatabaseService();
  final cefrService = CEFRService();
  final srsService = SRSService(db: db);

  // SettingsProvider owns the LLMService lifecycle.
  // It creates the appropriate backend (Ollama, Direct FFI, or Gemma)
  // based on user settings, and provides the LLMService to other providers.
  final settingsProvider = SettingsProvider(db: db);

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: db),
        Provider<CEFRService>.value(value: cefrService),
        ChangeNotifierProvider.value(value: settingsProvider..initialize()),

        // ChatProvider and TranslationService get LLMService from SettingsProvider.
        // When the backend changes, SettingsProvider.llmService is updated,
        // and on the next chat call the new backend is used automatically.
        ChangeNotifierProxyProvider<SettingsProvider, ChatProvider>(
          create: (context) {
            // Create with a placeholder — will be updated immediately by the proxy
            final settings = context.read<SettingsProvider>();
            return ChatProvider(
              llmService: settings.llmService,
              db: db,
              translationService: TranslationService(
                llmService: settings.llmService,
              ),
              cefrService: cefrService,
              srsService: srsService,
            );
          },
          update: (_, settings, previous) {
            // Update the LLM service reference when backend changes
            if (previous != null && !settings.isLoading) {
              previous.llmService = settings.llmService;
            }
            return previous!;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => SRSProvider(srsService: srsService),
        ),
        ChangeNotifierProvider(
          create: (_) => LessonProvider(db: db)..loadProgress(),
        ),
      ],
      child: const ZabanApp(),
    ),
  );
}

class ZabanApp extends StatelessWidget {
  const ZabanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaban',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (settings.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading Zaban...'),
              SizedBox(height: 4),
              Text(
                'در حال بارگذاری زبان...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'config/theme.dart';
import 'services/database_service.dart';
import 'services/translation_service.dart';
import 'services/cefr_service.dart';
import 'services/srs_service.dart';
import 'services/tts_service.dart';
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

  // Warm the Kokoro TTS server on startup — first synthesis after cold
  // start is slow because it lazy-loads the voice embedding + vocoder.
  // Throw away the result; we just want the model resident.
  final ttsService = TTSService();
  // ignore: discarded_futures
  ttsService.synthesize('.').then((_) {}).catchError((_) {});
  // Clean up stale TTS cache files (>7 days old) in the background.
  // ignore: discarded_futures
  ttsService.cleanCache().catchError((_) {});

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
            // `previous` is null only if create() hasn't run yet (edge case
            // during provider initialization). Fall back to constructing a
            // fresh ChatProvider rather than force-unwrapping null.
            final provider = previous ??
                ChatProvider(
                  llmService: settings.llmService,
                  db: db,
                  translationService: TranslationService(
                    llmService: settings.llmService,
                  ),
                  cefrService: cefrService,
                  srsService: srsService,
                );
            // Update the LLM service reference when backend changes
            if (!settings.isLoading) {
              provider.llmService = settings.llmService;
            }
            return provider;
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
    // Watch themeMode from SettingsProvider so hot-switching works immediately.
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'Zaban',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.isLoading ? ThemeMode.system : settings.themeMode,
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WindowListener {
  @override
  void initState() {
    super.initState();
    // Register for window close so we can flush SQLite WAL before exit.
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// Called when the user closes the window (X button / Alt+F4).
  /// Checkpoints the SQLite WAL and then destroys the window.
  @override
  Future<void> onWindowClose() async {
    // Grab the DatabaseService instance from the Provider tree and close it.
    // This flushes the SQLite WAL before the process exits.
    await context.read<DatabaseService>().close();
    await windowManager.destroy();
  }

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

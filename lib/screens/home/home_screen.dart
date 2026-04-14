import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/srs_provider.dart';
import '../../widgets/cefr_badge.dart';
import '../../widgets/model_status_indicator.dart';
import '../chat/chat_screen.dart';
import '../lessons/lessons_screen.dart';
import '../vocabulary/vocabulary_screen.dart';
import '../pronunciation/pronunciation_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().updateStreak();
      context.read<SRSProvider>().refreshStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final profile = settings.profile;

    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Z',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Zaban',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ModelStatusIndicator(
                        status: settings.backendStatus,
                        modelName: profile.selectedModel,
                      ),
                      const SizedBox(height: 8),
                      CEFRBadge(level: profile.cefrLevel),
                    ],
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: Text('Chat'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school),
                label: Text('Lessons'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.book_outlined),
                selectedIcon: Icon(Icons.book),
                label: Text('Words'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.mic_outlined),
                selectedIcon: Icon(Icons.mic),
                label: Text('Speak'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main content
          Expanded(
            child: _buildPage(settings),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(SettingsProvider settings) {
    return switch (_selectedIndex) {
      0 => _DashboardPage(
        onNavigate: (index) => setState(() => _selectedIndex = index),
      ),
      1 => const ChatScreen(),
      2 => LessonsScreen(
        onStartScenario: () => setState(() => _selectedIndex = 1),
      ),
      3 => const VocabularyScreen(),
      4 => const PronunciationScreen(),
      5 => const SettingsScreen(),
      _ => const Center(child: Text('Page not found')),
    };
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.onNavigate});
  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final srs = context.watch<SRSProvider>();
    final profile = settings.profile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name != null
                          ? 'Welcome back, ${profile.name}!'
                          : 'Welcome to Zaban!',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (profile.nameFa != null) ...[
                      const SizedBox(height: 4),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(
                          '!${profile.nameFa} ,خوش آمدید',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CEFRBadge(level: profile.cefrLevel, showLabel: true),
                        const SizedBox(width: 16),
                        Text(
                          profile.learningGoal.nameEn,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Streak display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '${profile.currentStreak}',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Day Streak',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Quick actions
          Text('Quick Start', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              _QuickActionCard(
                icon: Icons.chat_bubble_outline,
                title: 'Free Chat',
                titleFa: 'مکالمه آزاد',
                description: 'Practice conversation at your level',
                color: Colors.blue,
                onTap: () => onNavigate(1),
              ),
              const SizedBox(width: 12),
              _QuickActionCard(
                icon: Icons.school_outlined,
                title: 'Lessons',
                titleFa: 'درس‌ها',
                description: 'Guided scenarios & exercises',
                color: Colors.green,
                onTap: () => onNavigate(2),
              ),
              const SizedBox(width: 12),
              _QuickActionCard(
                icon: Icons.style_outlined,
                title: 'Review Cards',
                titleFa: 'مرور کارت‌ها',
                description: '${srs.stats?.dueToday ?? 0} cards due today',
                color: Colors.orange,
                onTap: () => onNavigate(3),
              ),
              const SizedBox(width: 12),
              _QuickActionCard(
                icon: Icons.mic_outlined,
                title: 'Pronunciation',
                titleFa: 'تلفظ',
                description: 'Practice speaking skills',
                color: Colors.purple,
                onTap: () => onNavigate(4),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Stats overview
          Text('Your Progress', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                icon: Icons.chat,
                value: '${profile.totalConversations}',
                label: 'Conversations',
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.timer,
                value: '${profile.totalMinutes}',
                label: 'Minutes',
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.book,
                value: '${profile.vocabularyCount}',
                label: 'Words Learned',
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.local_fire_department,
                value: '${profile.longestStreak}',
                label: 'Best Streak',
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Connection status
          if (settings.backendStatus != null && !settings.backendStatus!.isReady)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ollama is not running',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.red.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Start Ollama to enable AI conversations. Run: ollama serve',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(
                              'برای فعال‌سازی مکالمات هوش مصنوعی، Ollama را اجرا کنید: ollama serve',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => settings.refreshBackendStatus(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.titleFa,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String titleFa;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    titleFa,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

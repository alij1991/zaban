import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/lesson.dart';
import '../../models/cefr_level.dart';
import '../../providers/lesson_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/cefr_badge.dart';
import '../../widgets/bilingual_text.dart';

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key, this.onStartScenario});

  /// Called after a scenario conversation starts — should navigate to Chat tab.
  final VoidCallback? onStartScenario;

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LessonProvider>().loadProgress();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lessons = context.watch<LessonProvider>();

    return Column(
      children: [
        // Header with filters
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lessons & Scenarios',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'درس‌ها و سناریوها',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                children: [
                  // Domain filter
                  _FilterChipGroup<LessonDomain?>(
                    label: 'Topic',
                    selected: lessons.selectedDomain,
                    options: [null, ...LessonDomain.values],
                    labelBuilder: (d) =>
                        d == null ? 'All' : '${d.icon} ${d.nameEn}',
                    onSelected: (d) => lessons.setDomainFilter(d),
                  ),
                  const SizedBox(width: 16),
                  // Level filter
                  _FilterChipGroup<CEFRLevel?>(
                    label: 'Level',
                    selected: lessons.selectedLevel,
                    options: [null, ...CEFRLevel.values.take(4)],
                    labelBuilder: (l) => l?.code ?? 'All',
                    onSelected: (l) => lessons.setLevelFilter(l),
                  ),
                ],
              ),
              ),
            ],
          ),
        ),

        // Scenario cards
        Expanded(
          child: lessons.filteredScenarios.isEmpty
              ? const Center(child: Text('No scenarios match the selected filters.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lessons.filteredScenarios.length,
                  itemBuilder: (context, index) {
                    final scenario = lessons.filteredScenarios[index];
                    final progress = lessons.getProgress(scenario.id);
                    return _ScenarioCard(
                      scenario: scenario,
                      progress: progress,
                      onStarted: widget.onStartScenario,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChipGroup<T> extends StatelessWidget {
  const _FilterChipGroup({
    required this.label,
    required this.selected,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String label;
  final T selected;
  final List<T> options;
  final String Function(T) labelBuilder;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: options.map((option) {
        final isSelected = option == selected;
        return ChoiceChip(
          label: Text(labelBuilder(option)),
          selected: isSelected,
          onSelected: (_) => onSelected(option),
          labelStyle: TextStyle(fontSize: 12),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.scenario, this.progress, this.onStarted});
  final Scenario scenario;
  final LessonProgress? progress;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _startScenario(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Domain icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    scenario.domain.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: BilingualText(
                            english: scenario.titleEn,
                            persian: scenario.titleFa,
                            englishStyle: Theme.of(context).textTheme.titleSmall,
                            persianStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                            ),
                          ),
                        ),
                        CEFRBadge(level: scenario.cefrLevel, size: CEFRBadgeSize.small),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scenario.descriptionEn,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (scenario.targetVocabulary.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: scenario.targetVocabulary.take(5).map(
                          (word) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              word,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  if (progress != null && progress!.completedCount > 0) ...[
                    Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
                    Text(
                      '${progress!.completedCount}x',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Icon(Icons.play_circle_outline, size: 28),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startScenario(BuildContext context) {
    final chat = context.read<ChatProvider>();
    chat.startConversation(
      level: scenario.cefrLevel,
      scenario: scenario,
    );
    // Auto-navigate to the Chat tab
    onStarted?.call();
  }
}

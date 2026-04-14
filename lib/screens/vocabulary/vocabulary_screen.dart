import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/srs_provider.dart';
import '../../services/database_service.dart';
import '../../services/srs_service.dart';
import '../../models/vocabulary.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SRSProvider>().loadDueCards();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vocabulary & Review',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'واژگان و مرور',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Flashcard Review'),
                  Tab(text: 'Word List'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FlashcardReview(),
              _WordList(),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlashcardReview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final srs = context.watch<SRSProvider>();
    final stats = srs.stats;

    if (srs.isSessionComplete && srs.reviewedCount > 0) {
      return _ReviewComplete(
        reviewed: srs.reviewedCount,
        correct: srs.correctCount,
        onRestart: () => srs.loadDueCards(),
      );
    }

    if (srs.dueCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.celebration,
              size: 64,
              color: Colors.green.withAlpha(150),
            ),
            const SizedBox(height: 16),
            Text(
              'No cards due for review!',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'هیچ کارتی برای مرور نیست!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'New cards are created automatically from conversations.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (stats != null) ...[
              const SizedBox(height: 24),
              _SRSStatsBar(stats: stats),
            ],
          ],
        ),
      );
    }

    final card = srs.currentCard!;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(
                    '${srs.currentIndex + 1} / ${srs.dueCards.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (srs.currentIndex + 1) / srs.dueCards.length,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Card
            Card(
              elevation: 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    // Front (English word)
                    Text(
                      card.front,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (card.contextSentence != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        card.contextSentence!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    if (srs.showAnswer) ...[
                      const Divider(height: 32),
                      // Back (Persian translation + context)
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(
                          card.back,
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (card.contextTranslation != null) ...[
                        const SizedBox(height: 8),
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: Text(
                            card.contextTranslation!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            if (!srs.showAnswer)
              ElevatedButton(
                onPressed: srs.revealAnswer,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
                child: const Text('Show Answer (نمایش پاسخ)'),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RatingButton(
                    label: 'Again',
                    labelFa: 'دوباره',
                    color: Colors.red,
                    onTap: () => srs.rateCard(1),
                  ),
                  const SizedBox(width: 8),
                  _RatingButton(
                    label: 'Hard',
                    labelFa: 'سخت',
                    color: Colors.orange,
                    onTap: () => srs.rateCard(3),
                  ),
                  const SizedBox(width: 8),
                  _RatingButton(
                    label: 'Good',
                    labelFa: 'خوب',
                    color: Colors.green,
                    onTap: () => srs.rateCard(4),
                  ),
                  const SizedBox(width: 8),
                  _RatingButton(
                    label: 'Easy',
                    labelFa: 'آسان',
                    color: Colors.blue,
                    onTap: () => srs.rateCard(5),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.labelFa,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String labelFa;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withAlpha(20),
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(80)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(labelFa, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _ReviewComplete extends StatelessWidget {
  const _ReviewComplete({
    required this.reviewed,
    required this.correct,
    required this.onRestart,
  });

  final int reviewed;
  final int correct;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final accuracy = reviewed > 0 ? (correct / reviewed * 100).round() : 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'Review Complete!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('$correct / $reviewed correct ($accuracy%)'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRestart,
            child: const Text('Review Again'),
          ),
        ],
      ),
    );
  }
}

class _SRSStatsBar extends StatelessWidget {
  const _SRSStatsBar({required this.stats});
  final SRSStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MiniStat('New', '${stats.newCards}', Colors.blue),
        const SizedBox(width: 16),
        _MiniStat('Learning', '${stats.learning}', Colors.orange),
        const SizedBox(width: 16),
        _MiniStat('Mature', '${stats.mature}', Colors.green),
        const SizedBox(width: 16),
        _MiniStat('Total', '${stats.totalCards}', Colors.grey),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WordList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseService>();

    return FutureBuilder<List<VocabularyItem>>(
      future: db.getVocabulary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final words = snapshot.data ?? [];
        if (words.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No vocabulary yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Words you encounter in conversations will appear here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            return Card(
              child: ListTile(
                title: Text(word.word),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(word.translation),
                    ),
                    if (word.exampleSentence != null)
                      Text(
                        word.exampleSentence!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      word.cefrLevel.code,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      '${word.timesEncountered}x seen',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

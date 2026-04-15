import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cefr_level.dart';
import '../../models/flashcard.dart';
import '../../models/vocabulary.dart';
import '../../providers/settings_provider.dart';
import '../../providers/srs_provider.dart';
import '../../services/database_service.dart';
import '../../services/srs_service.dart';
import '../../services/translation_service.dart';
import '../../services/tts_service.dart';

/// Shared word-pronunciation helper — reuses one AudioPlayer + TTSService
/// so replays hit the Kokoro on-disk cache instead of re-synthesizing.
class _WordAudio {
  _WordAudio._();
  static final _WordAudio instance = _WordAudio._();

  final TTSService _tts = TTSService();
  final AudioPlayer _player = AudioPlayer();

  Future<void> speak(String word) async {
    if (word.trim().isEmpty) return;
    try {
      final path = await _tts.synthesize(word);
      if (path == null) return;
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('TTS playback failed: $e');
    }
  }
}

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
              _FlashcardReview(onAddWord: () => _openAddWordDialog(context)),
              _WordList(onAddWord: () => _openAddWordDialog(context)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / edit word dialog
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _openAddWordDialog(
  BuildContext context, {
  VocabularyItem? existing,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _AddWordDialog(existing: existing),
  );
}

class _AddWordDialog extends StatefulWidget {
  const _AddWordDialog({this.existing});
  final VocabularyItem? existing;

  @override
  State<_AddWordDialog> createState() => _AddWordDialogState();
}

class _AddWordDialogState extends State<_AddWordDialog> {
  late final TextEditingController _word;
  late final TextEditingController _translation;
  late final TextEditingController _phonetic;
  late final TextEditingController _example;
  late final TextEditingController _exampleFa;
  late final TextEditingController _pos;
  late CEFRLevel _level;
  bool _looking = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _word = TextEditingController(text: e?.word ?? '');
    _translation = TextEditingController(text: e?.translation ?? '');
    _phonetic = TextEditingController(text: e?.phonetic ?? '');
    _example = TextEditingController(text: e?.exampleSentence ?? '');
    _exampleFa = TextEditingController(text: e?.exampleTranslation ?? '');
    _pos = TextEditingController(text: e?.partOfSpeech ?? '');
    _level = e?.cefrLevel ??
        context.read<SettingsProvider>().profile.cefrLevel;
  }

  @override
  void dispose() {
    _word.dispose();
    _translation.dispose();
    _phonetic.dispose();
    _example.dispose();
    _exampleFa.dispose();
    _pos.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final word = _word.text.trim();
    if (word.isEmpty) return;
    setState(() => _looking = true);
    try {
      final settings = context.read<SettingsProvider>();
      final svc = TranslationService(llmService: settings.llmService);
      final result = await svc.lookupWord(word);
      if (!mounted) return;
      setState(() {
        if (_translation.text.isEmpty && result.translation != '?') {
          _translation.text = result.translation;
        }
        if (_phonetic.text.isEmpty && result.finglish != '?') {
          _phonetic.text = result.finglish;
        }
        if (_pos.text.isEmpty && (result.partOfSpeech ?? '?') != '?') {
          _pos.text = result.partOfSpeech!;
        }
        if (_example.text.isEmpty && (result.example ?? '?') != '?') {
          _example.text = result.example!;
        }
        if (_exampleFa.text.isEmpty && (result.exampleFa ?? '?') != '?') {
          _exampleFa.text = result.exampleFa!;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lookup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _save() async {
    final word = _word.text.trim();
    final translation = _translation.text.trim();
    if (word.isEmpty || translation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Word and Persian translation are required.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<SRSProvider>().addWord(
            word: word,
            translation: translation,
            phonetic: _phonetic.text.trim().isEmpty ? null : _phonetic.text.trim(),
            partOfSpeech: _pos.text.trim().isEmpty ? null : _pos.text.trim(),
            exampleSentence:
                _example.text.trim().isEmpty ? null : _example.text.trim(),
            exampleTranslation: _exampleFa.text.trim().isEmpty
                ? null
                : _exampleFa.text.trim(),
            cefrLevel: _level,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit word' : 'Add word'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _word,
                enabled: !isEdit, // avoid breaking SRS id -> word binding
                decoration: InputDecoration(
                  labelText: 'English word',
                  hintText: 'e.g. delicious',
                  suffixIcon: _looking
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Look up with AI',
                          icon: const Icon(Icons.auto_awesome),
                          onPressed: _lookup,
                        ),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _translation,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Persian translation (ترجمه)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phonetic,
                      decoration: const InputDecoration(
                        labelText: 'Finglish / phonetic',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _pos,
                      decoration: const InputDecoration(
                        labelText: 'Part of speech',
                        hintText: 'noun, verb, adj',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _example,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Example sentence',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _exampleFa,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Example translation (ترجمه مثال)',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<CEFRLevel>(
                initialValue: _level,
                decoration: const InputDecoration(
                  labelText: 'CEFR level',
                ),
                items: CEFRLevel.values
                    .map((l) => DropdownMenuItem(
                          value: l,
                          child: Text('${l.code} — ${l.nameEn}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _level = v);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flashcard review tab
// ─────────────────────────────────────────────────────────────────────────────

class _FlashcardReview extends StatelessWidget {
  const _FlashcardReview({required this.onAddWord});
  final VoidCallback onAddWord;

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
      final hasAnyCards = (stats?.totalCards ?? 0) > 0;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Icon(
                  hasAnyCards ? Icons.celebration : Icons.school_outlined,
                  size: 64,
                  color: Colors.green.withAlpha(150),
                ),
                const SizedBox(height: 16),
                Text(
                  hasAnyCards
                      ? 'No cards due for review!'
                      : 'Build your vocabulary deck',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    hasAnyCards
                        ? 'هیچ کارتی برای مرور نیست!'
                        : 'دسته‌ی لغات خود را بسازید',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  hasAnyCards
                      ? 'Come back later — reviews are scheduled based on how well you remember each word.'
                      : 'Add words you want to learn. The tutor also captures new words during chat automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAddWord,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a word'),
                ),
                if (stats != null) ...[
                  const SizedBox(height: 32),
                  _SRSStatsBar(stats: stats),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final card = srs.currentCard!;
    final reverse = srs.reverseMode;

    // Choose prompt / answer based on review direction.
    final promptText = reverse ? card.back : card.front;
    final answerText = reverse ? card.front : card.back;
    final promptCtx = reverse ? card.contextTranslation : card.contextSentence;
    final answerCtx = reverse ? card.contextSentence : card.contextTranslation;
    final promptRtl = reverse;
    final answerRtl = !reverse;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header: direction toggle + progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _ReviewDirectionToggle(
                      reverse: reverse,
                      onChanged: (_) => srs.toggleReverseMode(),
                    ),
                    const SizedBox(height: 12),
                    Row(
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
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 3,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        // Prompt
                        Directionality(
                          textDirection:
                              promptRtl ? TextDirection.rtl : TextDirection.ltr,
                          child: Text(
                            promptText,
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // Speaker — only useful on English side.
                        if (!reverse)
                          IconButton(
                            tooltip: 'Play pronunciation',
                            icon: const Icon(Icons.volume_up_outlined),
                            onPressed: () =>
                                _WordAudio.instance.speak(card.front),
                          ),
                        if (promptCtx != null && promptCtx.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Directionality(
                            textDirection: promptRtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Text(
                              promptCtx,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],

                        if (srs.showAnswer) ...[
                          const Divider(height: 32),
                          Directionality(
                            textDirection: answerRtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Text(
                              answerText,
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (reverse)
                            IconButton(
                              tooltip: 'Play pronunciation',
                              icon: const Icon(Icons.volume_up_outlined),
                              onPressed: () =>
                                  _WordAudio.instance.speak(card.front),
                            ),
                          if (answerCtx != null && answerCtx.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Directionality(
                              textDirection: answerRtl
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                              child: Text(
                                answerCtx,
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
              ),
              const SizedBox(height: 12),
              _CardMetadata(card: card),
              const SizedBox(height: 16),

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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _RatingButton(
                      label: 'Again',
                      labelFa: 'دوباره',
                      interval: '<1d',
                      color: Colors.red,
                      onTap: () => srs.rateCard(1),
                    ),
                    _RatingButton(
                      label: 'Hard',
                      labelFa: 'سخت',
                      interval: _previewInterval(card, 3),
                      color: Colors.orange,
                      onTap: () => srs.rateCard(3),
                    ),
                    _RatingButton(
                      label: 'Good',
                      labelFa: 'خوب',
                      interval: _previewInterval(card, 4),
                      color: Colors.green,
                      onTap: () => srs.rateCard(4),
                    ),
                    _RatingButton(
                      label: 'Easy',
                      labelFa: 'آسان',
                      interval: _previewInterval(card, 5),
                      color: Colors.blue,
                      onTap: () => srs.rateCard(5),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview the next interval (days) for a quality rating without mutating the
/// card. Mirrors the SM-2 logic in Flashcard.review for quality >= 3.
String _previewInterval(Flashcard card, int quality) {
  if (quality < 3) return '<1d';
  int interval;
  if (card.repetitions == 0) {
    interval = 1;
  } else if (card.repetitions == 1) {
    interval = 6;
  } else {
    interval = (card.interval * card.easeFactor).round();
  }
  if (interval < 30) return '${interval}d';
  if (interval < 365) return '${(interval / 30).round()}mo';
  return '${(interval / 365).toStringAsFixed(1)}y';
}

class _ReviewDirectionToggle extends StatelessWidget {
  const _ReviewDirectionToggle({
    required this.reverse,
    required this.onChanged,
  });
  final bool reverse;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('EN → FA'),
          icon: Icon(Icons.visibility_outlined),
        ),
        ButtonSegment(
          value: true,
          label: Text('FA → EN'),
          icon: Icon(Icons.edit_outlined),
        ),
      ],
      selected: {reverse},
      onSelectionChanged: (s) => onChanged(s.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _CardMetadata extends StatelessWidget {
  const _CardMetadata({required this.card});
  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final reps = card.repetitions;
    final interval = card.interval;
    final ef = card.easeFactor;
    final status = reps == 0
        ? 'New'
        : interval < 21
            ? 'Learning'
            : 'Mature';
    final color = reps == 0
        ? Colors.blue
        : interval < 21
            ? Colors.orange
            : Colors.green;
    return Wrap(
      spacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _Chip(icon: Icons.flag_outlined, label: status, color: color),
        _Chip(
          icon: Icons.schedule,
          label: reps == 0 ? 'First review' : 'Interval: ${interval}d',
          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
        ),
        _Chip(
          icon: Icons.trending_up,
          label: 'Ease ${ef.toStringAsFixed(2)}',
          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.labelFa,
    required this.interval,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String labelFa;
  final String interval;
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(labelFa, style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 2),
          Text(interval,
              style: TextStyle(fontSize: 10, color: color.withAlpha(180))),
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

// ─────────────────────────────────────────────────────────────────────────────
// Word list tab
// ─────────────────────────────────────────────────────────────────────────────

class _WordList extends StatefulWidget {
  const _WordList({required this.onAddWord});
  final VoidCallback onAddWord;

  @override
  State<_WordList> createState() => _WordListState();
}

class _WordListState extends State<_WordList> {
  String _query = '';
  CEFRLevel? _levelFilter;
  int _reloadTick = 0;

  void _refresh() => setState(() => _reloadTick++);

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseService>();

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Search words…',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<CEFRLevel?>(
                    value: _levelFilter,
                    hint: const Text('All levels'),
                    onChanged: (v) => setState(() => _levelFilter = v),
                    items: [
                      const DropdownMenuItem<CEFRLevel?>(
                        value: null,
                        child: Text('All levels'),
                      ),
                      ...CEFRLevel.values.map(
                        (l) => DropdownMenuItem<CEFRLevel?>(
                          value: l,
                          child: Text(l.code),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<VocabularyItem>>(
                key: ValueKey(_reloadTick),
                future: db.getVocabulary(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final all = snapshot.data ?? [];
                  final filtered = all.where((w) {
                    if (_levelFilter != null && w.cefrLevel != _levelFilter) {
                      return false;
                    }
                    if (_query.trim().isEmpty) return true;
                    final q = _query.trim().toLowerCase();
                    return w.word.toLowerCase().contains(q) ||
                        w.translation.contains(q);
                  }).toList();

                  if (all.isEmpty) {
                    return _EmptyWordList(onAddWord: widget.onAddWord);
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No words match the current filter.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final word = filtered[index];
                      return _WordListTile(
                        word: word,
                        onChanged: _refresh,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add_word_fab',
            onPressed: () async {
              await _openAddWordDialog(context);
              _refresh();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add word'),
          ),
        ),
      ],
    );
  }
}

class _EmptyWordList extends StatelessWidget {
  const _EmptyWordList({required this.onAddWord});
  final VoidCallback onAddWord;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                'Add words you want to study, or let the tutor capture new '
                'words from chat automatically. Use the AI lookup button to '
                'fill in translation, phonetic, and an example.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAddWord,
                icon: const Icon(Icons.add),
                label: const Text('Add your first word'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordListTile extends StatelessWidget {
  const _WordListTile({required this.word, required this.onChanged});
  final VocabularyItem word;
  final VoidCallback onChanged;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete word?'),
        content: Text('"${word.word}" will be removed from your deck.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!context.mounted) return;
      await context.read<SRSProvider>().deleteWord(word.id);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Row(
          children: [
            Flexible(child: Text(word.word)),
            const SizedBox(width: 6),
            if (word.phonetic != null && word.phonetic!.isNotEmpty)
              Text(
                '/${word.phonetic}/',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(word.translation),
            ),
            if (word.exampleSentence != null &&
                word.exampleSentence!.isNotEmpty)
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
        leading: IconButton(
          tooltip: 'Play pronunciation',
          icon: const Icon(Icons.volume_up_outlined),
          onPressed: () => _WordAudio.instance.speak(word.word),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
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
            PopupMenuButton<String>(
              onSelected: (action) async {
                switch (action) {
                  case 'edit':
                    await _openAddWordDialog(context, existing: word);
                    onChanged();
                  case 'reset':
                    await context.read<SRSProvider>().resetCard(word.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Card reset — it will appear in your next review.'),
                        ),
                      );
                    }
                    onChanged();
                  case 'delete':
                    await _confirmDelete(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'reset',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Reset review'),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/cefr_level.dart';
import '../../models/flashcard.dart';
import '../../models/vocabulary.dart';
import '../../providers/settings_provider.dart';
import '../../providers/srs_provider.dart';
import '../../services/database_service.dart';
import '../../services/fsrs_algorithm.dart';
import '../../services/srs_service.dart';
import '../../services/translation_service.dart';
import '../../services/tts_service.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Audio lives here (not a static singleton) so it is properly disposed.
  final TTSService _tts = TTSService();
  late final AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCards();
    });
  }

  void _loadCards() {
    final settings = context.read<SettingsProvider>();
    context.read<SRSProvider>().loadDueCards(
      targetRetention: settings.profile.srsTargetRetention,
      dailyNewLimit: settings.profile.srsDailyNewLimit,
    );
  }

  Future<void> _speakWord(String word) async {
    if (word.trim().isEmpty) return;
    try {
      final path = await _tts.synthesize(word);
      if (path == null) return;
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('TTS playback failed: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          color: Theme.of(context).colorScheme.surface,
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(150),
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
              _FlashcardReview(
                onAddWord: () => _openAddWordDialog(context),
                onSpeakWord: _speakWord,
              ),
              _WordList(
                onAddWord: () => _openAddWordDialog(context),
                onSpeakWord: _speakWord,
              ),
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

  // Hold a single TranslationService for the lifetime of this dialog so the
  // LLM cache is not discarded between lookups.
  TranslationService? _translationSvc;

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
    _level =
        e?.cefrLevel ?? context.read<SettingsProvider>().profile.cefrLevel;
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

  TranslationService _getTranslationService() {
    final llm = context.read<SettingsProvider>().llmService;
    _translationSvc ??= TranslationService(llmService: llm);
    return _translationSvc!;
  }

  Future<void> _lookup() async {
    final word = _word.text.trim();
    if (word.isEmpty) return;
    setState(() => _looking = true);
    try {
      final result = await _getTranslationService().lookupWord(word);
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
            phonetic:
                _phonetic.text.trim().isEmpty ? null : _phonetic.text.trim(),
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
                enabled: !isEdit,
                decoration: InputDecoration(
                  labelText: 'English word',
                  hintText: 'e.g. delicious',
                  suffixIcon: _looking
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
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
                decoration: const InputDecoration(labelText: 'CEFR level'),
                items: CEFRLevel.values
                    .map(
                      (l) => DropdownMenuItem(
                        value: l,
                        child: Text('${l.code} — ${l.nameEn}'),
                      ),
                    )
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
                  width: 16,
                  height: 16,
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

class _FlashcardReview extends StatefulWidget {
  const _FlashcardReview({
    required this.onAddWord,
    required this.onSpeakWord,
  });
  final VoidCallback onAddWord;
  final Future<void> Function(String) onSpeakWord;

  @override
  State<_FlashcardReview> createState() => _FlashcardReviewState();
}

class _FlashcardReviewState extends State<_FlashcardReview> {
  // Focus node so keyboard shortcuts work without the user having to click
  // the card first. Auto-focused on build.
  final FocusNode _kbFocus = FocusNode(debugLabel: 'flashcard-review');

  @override
  void dispose() {
    _kbFocus.dispose();
    super.dispose();
  }

  /// Space / Enter → reveal, or grade Good if already revealed.
  /// 1–4 → Again / Hard / Good / Easy (only when the answer is shown).
  /// Matches Anki's muscle-memory bindings.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final srs = context.read<SRSProvider>();
    if (srs.currentCard == null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    // Reveal shortcuts
    if (!srs.showAnswer) {
      if (key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        srs.revealAnswer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Grading shortcuts (answer visible)
    int? grade;
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      grade = 1;
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      grade = 2;
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3 ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      grade = 3; // Good — the default muscle-memory action
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      grade = 4;
    }
    if (grade == null) return KeyEventResult.ignored;
    srs.rateCard(grade);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final srs = context.watch<SRSProvider>();
    final stats = srs.stats;

    // Keep the focus node focused whenever this widget is visible so
    // shortcuts work without a pre-click.
    if (!_kbFocus.hasFocus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_kbFocus.hasFocus) _kbFocus.requestFocus();
      });
    }

    // ── Session complete ────────────────────────────────────────────────────
    if (srs.isSessionComplete && srs.reviewedCount > 0) {
      return _ReviewComplete(
        reviewed: srs.reviewedCount,
        correct: srs.correctCount,
        elapsed: srs.sessionElapsed,
        remainingDue:
            (stats?.dueToday ?? 0) - srs.reviewedCount > 0
                ? (stats?.dueToday ?? 0) - srs.reviewedCount
                : 0,
        onRestart: srs.endSession,
      );
    }

    // ── Empty / no-due state ────────────────────────────────────────────────
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
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withAlpha(150),
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  hasAnyCards
                      ? 'Come back later — reviews are spaced based on how well you remember each word.'
                      : 'Add words you want to learn. The tutor also captures new words during chat automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: widget.onAddWord,
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

    // ── Active review ───────────────────────────────────────────────────────
    final card = srs.currentCard!;
    final reverse = srs.reverseMode;
    final targetRetention = srs.targetRetention;

    final promptText = reverse ? card.back : card.front;
    final answerText = reverse ? card.front : card.back;
    final promptCtx =
        reverse ? card.contextTranslation : card.contextSentence;
    final answerCtx =
        reverse ? card.contextSentence : card.contextTranslation;

    // True number of cards due in the DB (uncapped). If this exceeds the
    // loaded session size the user is behind — surface it in the header.
    final trueDueToday = stats?.dueToday ?? srs.dueCards.length;
    final backlog = trueDueToday - srs.dueCards.length;

    return Focus(
      focusNode: _kbFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              // ── Session cap warning ───────────────────────────────────────
              if (srs.sessionLong)
                _SessionTimerBanner(
                  elapsed: srs.sessionElapsed,
                  hardCap: srs.sessionCapReached,
                ),

              // ── Header: direction toggle + progress ───────────────────────
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
                          '${srs.currentIndex + 1} / ${srs.dueCards.length}'
                          '${backlog > 0 ? "  (+$backlog more due)" : ""}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: backlog > 0 ? Colors.orange : null,
                                fontWeight:
                                    backlog > 0 ? FontWeight.w600 : null,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(srs.sessionElapsed),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: srs.sessionLong
                                    ? Colors.orange
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha(100),
                              ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: (srs.currentIndex + 1) /
                                srs.dueCards.length,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Keyboard: Space = flip, 1–4 = Again/Hard/Good/Easy',
                          child: Icon(
                            Icons.keyboard_outlined,
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(90),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Card ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 3,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Directionality(
                          textDirection: reverse
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Text(
                            promptText,
                            style:
                                Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (!reverse)
                          IconButton(
                            tooltip: 'Play pronunciation',
                            icon: const Icon(Icons.volume_up_outlined),
                            onPressed: () => widget.onSpeakWord(card.front),
                          ),
                        if (promptCtx != null && promptCtx.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Directionality(
                            textDirection: reverse
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Text(
                              promptCtx,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha(150),
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        if (srs.showAnswer) ...[
                          const Divider(height: 32),
                          Directionality(
                            textDirection: reverse
                                ? TextDirection.ltr
                                : TextDirection.rtl,
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
                              onPressed: () => widget.onSpeakWord(card.front),
                            ),
                          if (answerCtx != null &&
                              answerCtx.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Directionality(
                              textDirection: reverse
                                  ? TextDirection.ltr
                                  : TextDirection.rtl,
                              child: Text(
                                answerCtx,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withAlpha(150),
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

              // ── Actions ──────────────────────────────────────────────────
              if (!srs.showAnswer)
                ElevatedButton(
                  onPressed: srs.revealAnswer,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(220, 48),
                  ),
                  child: const Text('Show Answer  (نمایش پاسخ)'),
                )
              else
                // FSRS uses 4 grades: Again / Hard / Good / Easy
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
                      interval: card.previewInterval(2,
                          targetRetention: targetRetention),
                      color: Colors.orange,
                      onTap: () => srs.rateCard(2),
                    ),
                    _RatingButton(
                      label: 'Good',
                      labelFa: 'خوب',
                      interval: card.previewInterval(3,
                          targetRetention: targetRetention),
                      color: Colors.green,
                      onTap: () => srs.rateCard(3),
                    ),
                    _RatingButton(
                      label: 'Easy',
                      labelFa: 'آسان',
                      interval: card.previewInterval(4,
                          targetRetention: targetRetention),
                      color: Colors.blue,
                      onTap: () => srs.rateCard(4),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ── Session timer banner ───────────────────────────────────────────────────

class _SessionTimerBanner extends StatelessWidget {
  const _SessionTimerBanner({
    required this.elapsed,
    required this.hardCap,
  });
  final Duration elapsed;
  final bool hardCap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: (hardCap ? Colors.orange : Colors.amber).withAlpha(30),
        border: Border.all(
          color: (hardCap ? Colors.orange : Colors.amber).withAlpha(100),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            hardCap ? Icons.timer_off_outlined : Icons.timer_outlined,
            size: 18,
            color: hardCap ? Colors.orange : Colors.amber.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hardCap
                  ? 'You\'ve been reviewing for ${elapsed.inMinutes} min — finish this card then take a break! (استراحت کنید)'
                  : 'Great effort — ${elapsed.inMinutes} min in! Almost done.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ── Direction toggle ───────────────────────────────────────────────────────

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
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }
}

// ── Card metadata chips ────────────────────────────────────────────────────

class _CardMetadata extends StatelessWidget {
  const _CardMetadata({required this.card});
  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final status = card.status;
    final (label, color) = switch (status) {
      CardStatus.newCard => ('New', Colors.blue),
      CardStatus.learning => ('Learning', Colors.orange),
      CardStatus.young => ('Young', Colors.amber.shade700),
      CardStatus.mature => ('Mature', Colors.green),
    };
    return Wrap(
      spacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _Chip(icon: Icons.flag_outlined, label: label, color: color),
        _Chip(
          icon: Icons.schedule,
          label: card.repetitions == 0
              ? 'First review'
              : 'Interval: ${card.scheduledInterval}d',
          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
        ),
        _Chip(
          icon: Icons.psychology_outlined,
          label: 'D ${card.difficulty.toStringAsFixed(1)}',
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

// ── Rating buttons (FSRS 4-grade) ─────────────────────────────────────────

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
          Text(
            interval,
            style: TextStyle(fontSize: 10, color: color.withAlpha(180)),
          ),
        ],
      ),
    );
  }
}

// ── Review complete screen ─────────────────────────────────────────────────

class _ReviewComplete extends StatelessWidget {
  const _ReviewComplete({
    required this.reviewed,
    required this.correct,
    required this.elapsed,
    required this.remainingDue,
    required this.onRestart,
  });
  final int reviewed;
  final int correct;
  final Duration elapsed;

  /// Cards still due in the deck after this session (0 = fully caught up).
  final int remainingDue;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final accuracy = reviewed > 0 ? (correct / reviewed * 100).round() : 0;
    // Motivational framing: colour the accuracy row by performance.
    final accuracyColor = accuracy >= 85
        ? Colors.green
        : (accuracy >= 70 ? Colors.amber.shade700 : Colors.orange);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 72, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Session Complete!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'جلسه تمام شد!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(150),
                      ),
                ),
              ),
              const SizedBox(height: 24),
              _StatRow('Cards reviewed', '$reviewed'),
              _StatRow(
                'Correct',
                '$correct / $reviewed  ($accuracy %)',
                valueColor: accuracyColor,
              ),
              _StatRow('Time', _formatDuration(elapsed)),
              if (remainingDue > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(25),
                    border: Border.all(color: Colors.orange.withAlpha(80)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions,
                          size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$remainingDue more card${remainingDue == 1 ? "" : "s"} due today '
                          '(${remainingDue == 1 ? "کارت" : "کارت‌های"} باقی‌مانده).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.refresh),
                label: Text(remainingDue > 0
                    ? 'Keep reviewing'
                    : 'Check for more cards'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
          ),
        ],
      ),
    );
  }
}

// ── SRS stats bar (shown when no cards due) ────────────────────────────────

class _SRSStatsBar extends StatelessWidget {
  const _SRSStatsBar({required this.stats});
  final SRSStats stats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _MiniStat('New', '${stats.newCards}', Colors.blue),
        _MiniStat('Learning', '${stats.learning}', Colors.orange),
        _MiniStat('Mature', '${stats.mature}', Colors.green),
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
            fontSize: 20,
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
  const _WordList({required this.onAddWord, required this.onSpeakWord});
  final VoidCallback onAddWord;
  final Future<void> Function(String) onSpeakWord;

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
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
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
                      return _WordListTile(
                        word: filtered[index],
                        onChanged: _refresh,
                        onSpeakWord: widget.onSpeakWord,
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
  const _WordListTile({
    required this.word,
    required this.onChanged,
    required this.onSpeakWord,
  });
  final VocabularyItem word;
  final VoidCallback onChanged;
  final Future<void> Function(String) onSpeakWord;

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
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(120),
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
          onPressed: () => onSpeakWord(word.word),
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
                  '${word.timesEncountered}× seen',
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
                          content: Text(
                              'Card reset — it will appear in your next session.'),
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
                    leading:
                        Icon(Icons.delete_outline, color: Colors.red),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
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

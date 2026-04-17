import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../utils/phoneme_mappings.dart';
import '../../models/pronunciation_result.dart';
import '../../services/audio_service.dart';
import '../../services/tts_service.dart';
import '../../services/whisper_transcription_service.dart';

class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({super.key});

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _audioService = AudioService();
  final _ttsService = TTSService();
  final _whisperService = WhisperTranscriptionService();
  // Use `audioplayers` for playback (miniaudio-backed, works on Windows +
  // macOS + Linux). Previously we shelled out to PowerShell's SoundPlayer,
  // which was Windows-only and would silently no-op on macOS.
  final AudioPlayer _playbackPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioService.dispose();
    _ttsService.dispose();
    _whisperService.dispose();
    _playbackPlayer.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    final path = await _ttsService.synthesize(text);
    if (path != null) {
      try {
        await _playbackPlayer.stop();
        await _playbackPlayer.play(DeviceFileSource(path));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('TTS not available. Run: python -m kokoro.serve --port 8880')),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TTS not available. Run: python -m kokoro.serve --port 8880')),
      );
    }
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
              Text('Pronunciation Practice',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text('تمرین تلفظ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                    )),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Persian Challenges'),
                  Tab(text: 'Minimal Pairs'),
                  Tab(text: 'Practice'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PersianChallengesTab(
                onPractice: (issue) {
                  // Switch to practice tab
                  _tabController.animateTo(2);
                },
                onListen: _speak,
              ),
              _MinimalPairsTab(onListen: _speak),
              _PracticeTab(
                audioService: _audioService,
                whisperService: _whisperService,
                onListen: _speak,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// === Persian Challenges Tab ===

class _PersianChallengesTab extends StatelessWidget {
  const _PersianChallengesTab({required this.onPractice, required this.onListen});
  final void Function(PersianPhoneIssue) onPractice;
  final void Function(String) onListen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('The 7 key pronunciation challenges for Persian speakers:',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text('۷ چالش کلیدی تلفظ برای فارسی‌زبانان:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              )),
        ),
        const SizedBox(height: 16),
        ...PersianPhoneIssue.values.map(
          (issue) => _ChallengeCard(
            issue: issue,
            onPractice: () => onPractice(issue),
            onListen: onListen,
          ),
        ),
      ],
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.issue,
    required this.onPractice,
    required this.onListen,
  });
  final PersianPhoneIssue issue;
  final VoidCallback onPractice;
  final void Function(String) onListen;

  @override
  Widget build(BuildContext context) {
    // Get example words for this issue
    final exampleWords = _getExampleWords(issue);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(issue.shortLabel.split(' ').first,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
          ),
        ),
        title: Text(issue.shortLabel),
        subtitle: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(issue.shortLabelFa,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              )),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.explanation, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(60),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(issue.explanationFa,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                ),
                // Example words with listen buttons
                if (exampleWords.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Example words:', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: exampleWords.take(5).map((word) => ActionChip(
                      avatar: const Icon(Icons.volume_up, size: 14),
                      label: Text(word, style: const TextStyle(fontSize: 12)),
                      onPressed: () => onListen(word),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onPractice,
                  icon: const Icon(Icons.mic),
                  label: const Text('Practice This Sound'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getExampleWords(PersianPhoneIssue issue) {
    return switch (issue) {
      PersianPhoneIssue.thSubstitution => practiceWords['th_voiceless'] ?? [],
      PersianPhoneIssue.wvMerge => ['well', 'west', 'water', 'wine', 'wow'],
      PersianPhoneIssue.vowelQuality => ['sit', 'seat', 'full', 'fool', 'cat'],
      PersianPhoneIssue.consonantCluster => practiceWords['consonant_clusters'] ?? [],
      PersianPhoneIssue.wordStress => ['present', 'record', 'object', 'photograph'],
      PersianPhoneIssue.rhythm => ['interesting', 'comfortable', 'chocolate'],
      PersianPhoneIssue.intonation => ['Are you happy?', 'Do you like it?', 'Is it good?'],
    };
  }
}

// === Minimal Pairs Tab ===

class _MinimalPairsTab extends StatelessWidget {
  const _MinimalPairsTab({required this.onListen});
  final void Function(String) onListen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Minimal pairs help you hear and produce the difference between similar sounds.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text('جفت‌های حداقلی به شما کمک می‌کنند تفاوت بین صداهای مشابه را بشنوید.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              )),
        ),
        const SizedBox(height: 16),
        ...minimalPairs.entries.map(
          (entry) => _MinimalPairGroup(
            category: entry.key,
            pairs: entry.value,
            onListen: onListen,
          ),
        ),
      ],
    );
  }
}

class _MinimalPairGroup extends StatelessWidget {
  const _MinimalPairGroup({
    required this.category,
    required this.pairs,
    required this.onListen,
  });
  final String category;
  final List<List<String>> pairs;
  final void Function(String) onListen;

  @override
  Widget build(BuildContext context) {
    final displayName = switch (category) {
      'θ_t' => '/θ/ vs /t/ (thigh vs tie)',
      'ð_d' => '/ð/ vs /d/ (they vs day)',
      'w_v' => '/w/ vs /v/ (west vs vest)',
      'ɪ_iː' => '/ɪ/ vs /iː/ (sit vs seat)',
      'ʊ_uː' => '/ʊ/ vs /uː/ (full vs fool)',
      _ => category,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayName, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ...pairs.map(
              (pair) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => onListen(pair[0]),
                        borderRadius: BorderRadius.circular(8),
                        child: _WordChip(word: pair[0], color: Colors.blue),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.compare_arrows, size: 16, color: Colors.grey),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => onListen(pair[1]),
                        borderRadius: BorderRadius.circular(8),
                        child: _WordChip(word: pair[1], color: Colors.orange),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.volume_up, size: 18),
                      onPressed: () {
                        // Speak first word, then second after delay
                        onListen(pair[0]);
                        Future.delayed(const Duration(seconds: 2), () {
                          onListen(pair[1]);
                        });
                      },
                      tooltip: 'Listen to both',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.color});
  final String word;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.volume_up, size: 14, color: color.withAlpha(150)),
          const SizedBox(width: 6),
          Text(word,
              style: TextStyle(fontWeight: FontWeight.w500, color: color.withAlpha(200))),
        ],
      ),
    );
  }
}

// === Practice Tab ===

class _PracticeTab extends StatefulWidget {
  const _PracticeTab({
    required this.audioService,
    required this.whisperService,
    required this.onListen,
  });
  final AudioService audioService;
  final WhisperTranscriptionService whisperService;
  final void Function(String) onListen;

  @override
  State<_PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<_PracticeTab> {
  bool _isRecording = false;
  bool _isTranscribing = false;
  String? _userTranscription;
  String? _feedback;

  static const _targetSentence =
      'The three brothers think this weather is rather threatening.';

  Future<void> _startRecording() async {
    final hasPermission = await widget.audioService.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    await widget.audioService.startRecording();
    setState(() {
      _isRecording = true;
      _userTranscription = null;
      _feedback = null;
    });
  }

  Future<void> _stopAndCompare() async {
    final path = await widget.audioService.stopRecording();
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
    });

    if (path == null) {
      setState(() => _isTranscribing = false);
      return;
    }

    // Check if Whisper is available
    final available = await widget.whisperService.isAvailable();
    if (!available) {
      setState(() => _isTranscribing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('STT server not running. Run: scripts\\start_services.bat'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    try {
      final transcription = await widget.whisperService
          .transcribeFile(path)
          .timeout(const Duration(seconds: 30));
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _userTranscription = transcription;
          _feedback = _compareSentences(_targetSentence, transcription ?? '');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTranscribing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transcription failed: $e')),
        );
      }
    }
  }

  String _compareSentences(String target, String spoken) {
    if (spoken.isEmpty) return 'No speech detected. Try speaking louder.';

    final targetWords = target.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
    final spokenWords = spoken.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));

    int correct = 0;
    final missed = <String>[];

    for (final word in targetWords) {
      if (spokenWords.contains(word)) {
        correct++;
      } else {
        missed.add(word);
      }
    }

    final accuracy = (correct / targetWords.length * 100).round();
    final buffer = StringBuffer('Accuracy: $accuracy%\n');

    if (accuracy == 100) {
      buffer.writeln('Excellent! Perfect pronunciation!');
    } else if (accuracy >= 80) {
      buffer.writeln('Good job! Almost there.');
    } else if (accuracy >= 50) {
      buffer.writeln('Keep practicing. You\'re improving!');
    } else {
      buffer.writeln('Try again — speak clearly and slowly.');
    }

    if (missed.isNotEmpty) {
      buffer.writeln('\nMissed words: ${missed.join(", ")}');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Pronunciation Practice',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Read the sentence aloud and compare your pronunciation.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),

              // Target sentence card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text('"$_targetSentence"',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('Tests: /θ/, /ð/, consonant clusters, word stress',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                          )),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => widget.onListen(_targetSentence),
                        icon: const Icon(Icons.volume_up, size: 16),
                        label: const Text('Listen to correct pronunciation'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Record button
              if (_isTranscribing)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Transcribing your speech...'),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _isRecording ? _stopAndCompare : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    backgroundColor: _isRecording ? Colors.red : null,
                    foregroundColor: _isRecording ? Colors.white : null,
                  ),
                ),

              // Results
              if (_userTranscription != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('You said:', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text('"$_userTranscription"',
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
              ],
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Feedback:', style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(_feedback!, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

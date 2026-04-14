import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../models/cefr_level.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/audio_service.dart';
import '../../services/tts_service.dart';
import '../../services/whisper_transcription_service.dart';
import '../../widgets/cefr_badge.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/error_correction_card.dart';
import 'widgets/voice_input_button.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();
  final _audioService = AudioService();
  final _ttsService = TTSService();
  final _whisperService = WhisperTranscriptionService();
  bool _showTranslation = false;
  String? _translatedText;
  String? _previousResponse;
  late final ChatProvider _chatProvider;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _chatProvider.addListener(_onChatChanged);
  }

  @override
  void dispose() {
    try { _currentTtsProcess?.kill(); } catch (_) {}
    _chatProvider.removeListener(_onChatChanged);
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _audioService.dispose();
    _ttsService.dispose();
    _whisperService.dispose();
    super.dispose();
  }

  int _lastSpokenMessageCount = 0;
  String? _lastSpokenConversationId;

  void _onChatChanged() {
    // Auto-scroll while generating — only when response actually grows
    if (_chatProvider.isGenerating && _chatProvider.currentResponse != _previousResponse) {
      _previousResponse = _chatProvider.currentResponse;
      _scrollToBottom();
    }

    // Reset speak counter when switching conversations (don't auto-speak history)
    final convId = _chatProvider.currentConversation?.id;
    if (convId != _lastSpokenConversationId) {
      _lastSpokenConversationId = convId;
      _lastSpokenMessageCount = _chatProvider.messages.length;
      return;
    }

    // Auto-speak each new finalized assistant message (not while streaming)
    if (!_chatProvider.isGenerating) {
      final msgs = _chatProvider.messages;
      if (msgs.length > _lastSpokenMessageCount) {
        final latest = msgs.last;
        _lastSpokenMessageCount = msgs.length;
        if (latest.role == MessageRole.assistant && latest.content.trim().isNotEmpty) {
          // Fire and forget — don't block UI; suppress error snackbars for auto-play
          _speak(latest.content, showErrors: false);
        }
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Process? _currentTtsProcess;

  /// Speak text via TTS. Cancels any previous playback so rapid sequential
  /// calls (e.g., auto-speak + manual replay) don't overlap.
  Future<void> _speak(String text, {bool showErrors = true}) async {
    // Kill any in-flight playback
    try {
      _currentTtsProcess?.kill();
    } catch (_) {}
    _currentTtsProcess = null;

    final path = await _ttsService.synthesize(text);
    if (path == null) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('TTS not available. Run: scripts/start_services.bat')),
        );
      }
      return;
    }

    await _audioService.initialize();
    try {
      final proc = await Process.start('powershell', [
        '-NoProfile', '-Command',
        '(New-Object Media.SoundPlayer "$path").PlaySync()',
      ]);
      _currentTtsProcess = proc;
      await proc.exitCode;
      if (identical(_currentTtsProcess, proc)) _currentTtsProcess = null;
    } catch (_) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio playback failed.')),
        );
      }
    }
  }

  void _sendMessage(ChatProvider chat, CEFRLevel level) {
    final text = _textController.text.trim();
    if (text.isEmpty || chat.isGenerating) return;

    _textController.clear();
    chat.sendMessage(text, level: level);
    _scrollToBottom();
    _inputFocusNode.requestFocus();
  }

  void _startNewConversation(ChatProvider chat, CEFRLevel level) {
    chat.startConversation(level: level);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final settings = context.watch<SettingsProvider>();
    final level = settings.profile.cefrLevel;

    return Column(
      children: [
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              if (chat.currentConversation != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => chat.clearConversation(),
                  tooltip: 'Back to conversation list',
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  chat.currentConversation?.title ?? 'Conversations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              CEFRBadge(level: level, showLabel: true),
              const SizedBox(width: 12),
              if (chat.currentConversation != null) ...[
                IconButton(
                  icon: Icon(
                    _showTranslation ? Icons.translate : Icons.translate_outlined,
                  ),
                  onPressed: () async {
                    if (!_showTranslation) {
                      _translatedText = await chat.translateLastMessage();
                    }
                    setState(() => _showTranslation = !_showTranslation);
                  },
                  tooltip: 'Translate (ترجمه)',
                ),
                IconButton(
                  icon: chat.isCheckingErrors
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.spellcheck),
                  onPressed: chat.isCheckingErrors
                      ? null
                      : () => chat.getCorrections(level),
                  tooltip: 'Check errors (بررسی خطاها)',
                ),
              ],
            ],
          ),
        ),

        // Chat content
        Expanded(
          child: chat.currentConversation == null
              ? _ConversationListOrStart(
                  onStartNew: () => _startNewConversation(chat, level),
                  chat: chat,
                  level: level,
                )
              : Column(
                  children: [
                    // Messages
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: chat.messages.length +
                            (chat.isGenerating ? 1 : 0) +
                            (_showTranslation && _translatedText != null ? 1 : 0) +
                            (chat.lastCorrections.isNotEmpty ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Regular messages
                          if (index < chat.messages.length) {
                            return ChatBubble(
                              message: chat.messages[index],
                              showTranslations: settings.profile.showTranslations,
                              onListen: _speak,
                            );
                          }

                          // Streaming response
                          final adjustedIndex = index - chat.messages.length;
                          if (chat.isGenerating && adjustedIndex == 0) {
                            return ChatBubble(
                              message: Message(
                                role: MessageRole.assistant,
                                content: chat.currentResponse.isEmpty
                                    ? '...'
                                    : chat.currentResponse,
                              ),
                              isStreaming: true,
                              showTranslations: false,
                            );
                          }

                          // Translation card
                          final correctionOffset = chat.isGenerating ? 1 : 0;
                          if (_showTranslation &&
                              _translatedText != null &&
                              adjustedIndex == correctionOffset) {
                            return _TranslationCard(text: _translatedText!);
                          }

                          // Corrections card
                          if (chat.lastCorrections.isNotEmpty) {
                            return ErrorCorrectionCard(
                              corrections: chat.lastCorrections,
                            );
                          }

                          return const SizedBox.shrink();
                        },
                      ),
                    ),

                    // Input area
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Voice input button — records audio and transcribes
                          VoiceInputButton(
                            audioService: _audioService,
                            whisperService: _whisperService,
                            enabled: !chat.isGenerating,
                            onTranscribed: (text) {
                              // Insert transcribed text and send
                              _textController.text = text;
                              _sendMessage(chat, level);
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: KeyboardListener(
                              focusNode: _keyboardFocusNode,
                              onKeyEvent: (event) {
                                if (event is KeyDownEvent &&
                                    event.logicalKey == LogicalKeyboardKey.enter &&
                                    !HardwareKeyboard.instance.isShiftPressed) {
                                  // Prevent the newline from being inserted
                                  _sendMessage(chat, level);
                                }
                              },
                              child: TextField(
                                controller: _textController,
                                focusNode: _inputFocusNode,
                                decoration: InputDecoration(
                                  hintText: 'Type your message... (پیام خود را بنویسید...)',
                                  hintStyle: TextStyle(color: Colors.grey.shade500),
                                  suffixIcon: chat.isGenerating
                                      ? IconButton(
                                          icon: const Icon(Icons.stop_circle, color: Colors.red),
                                          onPressed: () => chat.cancelGeneration(),
                                          tooltip: 'Stop generating (توقف)',
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.send),
                                          onPressed: () => _sendMessage(chat, level),
                                        ),
                                ),
                                maxLines: 3,
                                minLines: 1,
                                enabled: !chat.isGenerating,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ConversationListOrStart extends StatefulWidget {
  const _ConversationListOrStart({
    required this.onStartNew,
    required this.chat,
    required this.level,
  });

  final VoidCallback onStartNew;
  final ChatProvider chat;
  final CEFRLevel level;

  @override
  State<_ConversationListOrStart> createState() => _ConversationListOrStartState();
}

class _ConversationListOrStartState extends State<_ConversationListOrStart> {
  int _refreshKey = 0;

  Future<void> _confirmDelete(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text('"$title" will be permanently deleted.\n\n(این مکالمه برای همیشه حذف خواهد شد)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.chat.deleteConversation(id);
      if (mounted) setState(() => _refreshKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onStartNew = widget.onStartNew;
    final chat = widget.chat;
    final level = widget.level;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withAlpha(100),
            ),
            const SizedBox(height: 16),
            Text(
              'Start a Conversation',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'یک مکالمه شروع کنید',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Practice English with your AI tutor at ${level.code} level.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onStartNew,
              icon: const Icon(Icons.add),
              label: const Text('New Free Conversation'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            const SizedBox(height: 32),
            FutureBuilder(
              key: ValueKey(_refreshKey),
              future: chat.getHistory(limit: 10),
              builder: (context, snapshot) {
                final history = snapshot.data ?? [];
                if (history.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Conversations',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ...history.map(
                      (conv) => Dismissible(
                        key: ValueKey('conv_${conv.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          await _confirmDelete(conv.id, conv.title);
                          // Return false — we already removed it via setState,
                          // and returning true would remove it from the list before
                          // the FutureBuilder re-runs.
                          return false;
                        },
                        child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(conv.title),
                          subtitle: Text(
                            '${conv.cefrLevel.code} - ${conv.messageCount} messages',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDate(conv.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                tooltip: 'Delete (حذف)',
                                onPressed: () => _confirmDelete(conv.id, conv.title),
                              ),
                            ],
                          ),
                          onTap: () => chat.loadConversation(conv.id),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.translate, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Translation (ترجمه)',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

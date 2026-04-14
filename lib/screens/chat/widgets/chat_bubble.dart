import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.showTranslations = true,
    this.onListen,
  });

  final Message message;
  final bool isStreaming;
  final bool showTranslations;
  final void Function(String text)? onListen;

  bool get isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.school,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.65,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: isUser
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 24,
                      height: 12,
                      child: _TypingIndicator(
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                  if (showTranslations && message.translation != null) ...[
                    const Divider(height: 16),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        message.translation!,
                        style: TextStyle(
                          color: isUser
                              ? Colors.white70
                              : Theme.of(context).colorScheme.onSurface.withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (message.pronunciationScore != null) ...[
                    const SizedBox(height: 6),
                    _PronunciationScoreBadge(
                      score: message.pronunciationScore!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isUser) ...[
            const SizedBox(width: 4),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  iconSize: 14,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Copy',
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 14),
                  onPressed: onListen != null
                      ? () => onListen!(message.content)
                      : null,
                  iconSize: 14,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Listen (گوش دادن)',
                ),
              ],
            ),
          ],
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _PronunciationScoreBadge extends StatelessWidget {
  const _PronunciationScoreBadge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 0.8
        ? Colors.green
        : score >= 0.6
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '${(score * 100).round()}%',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.color});
  final Color color;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final offset = (_controller.value - index * 0.2).clamp(0.0, 1.0);
            final opacity = (1 - (offset * 2 - 1).abs()).clamp(0.3, 1.0);
            return Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color.withAlpha((opacity * 255).toInt()),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

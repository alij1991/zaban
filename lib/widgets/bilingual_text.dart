import 'package:flutter/material.dart';

/// Displays bilingual text with proper directionality.
/// English (LTR) and Persian (RTL) rendered correctly.
class BilingualText extends StatelessWidget {
  const BilingualText({
    super.key,
    required this.english,
    this.persian,
    this.englishStyle,
    this.persianStyle,
    this.showPersian = true,
    this.spacing = 4,
  });

  final String english;
  final String? persian;
  final TextStyle? englishStyle;
  final TextStyle? persianStyle;
  final bool showPersian;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            english,
            style: englishStyle ?? Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        if (showPersian && persian != null) ...[
          SizedBox(height: spacing),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              persian!,
              style: persianStyle ??
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A text widget that auto-detects direction based on content.
class AutoDirectionText extends StatelessWidget {
  const AutoDirectionText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final isRtl = _startsWithRtl(text);
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }

  static bool _startsWithRtl(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return false;
    final firstChar = trimmed.codeUnitAt(0);
    // Arabic/Persian Unicode ranges
    return (firstChar >= 0x0600 && firstChar <= 0x06FF) ||
        (firstChar >= 0xFB50 && firstChar <= 0xFDFF) ||
        (firstChar >= 0xFE70 && firstChar <= 0xFEFF);
  }
}

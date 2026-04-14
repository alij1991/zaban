import 'package:flutter/material.dart';
import '../models/cefr_level.dart';
import '../config/theme.dart';

class CEFRBadge extends StatelessWidget {
  const CEFRBadge({
    super.key,
    required this.level,
    this.size = CEFRBadgeSize.medium,
    this.showLabel = false,
  });

  final CEFRLevel level;
  final CEFRBadgeSize size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.cefrColor(level.code);
    final (fontSize, padH, padV) = switch (size) {
      CEFRBadgeSize.small => (11.0, 6.0, 2.0),
      CEFRBadgeSize.medium => (13.0, 10.0, 4.0),
      CEFRBadgeSize.large => (16.0, 14.0, 6.0),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(100)),
          ),
          child: Text(
            level.code,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Text(
            level.nameEn,
            style: TextStyle(fontSize: fontSize, color: color),
          ),
        ],
      ],
    );
  }
}

enum CEFRBadgeSize { small, medium, large }

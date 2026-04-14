import 'package:flutter/material.dart';
import '../../../models/message.dart';

class ErrorCorrectionCard extends StatelessWidget {
  const ErrorCorrectionCard({
    super.key,
    required this.corrections,
  });

  final List<CorrectionItem> corrections;

  @override
  Widget build(BuildContext context) {
    if (corrections.isEmpty) {
      return Card(
        color: Colors.green.shade50,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 12),
              Text(
                'No errors found! Great job! (عالی! بدون خطا!)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_fix_high,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Error Corrections (اصلاح خطاها)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...corrections.map(
              (c) => _CorrectionItemWidget(correction: c),
            ),
          ],
        ),
      ),
    );
  }
}

class _CorrectionItemWidget extends StatelessWidget {
  const _CorrectionItemWidget({required this.correction});
  final CorrectionItem correction;

  @override
  Widget build(BuildContext context) {
    final categoryColor = switch (correction.category) {
      'grammar' => Colors.blue,
      'vocabulary' => Colors.purple,
      'word_order' => Colors.orange,
      'pronunciation' => Colors.teal,
      _ => Colors.grey,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category badge
          if (correction.category != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: categoryColor.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                correction.category!.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: categoryColor,
                ),
              ),
            ),
          // Original → Corrected
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: correction.original,
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Colors.red,
                  ),
                ),
                const TextSpan(text: '  →  '),
                TextSpan(
                  text: correction.corrected,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // English explanation
          Text(
            correction.explanation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // Persian explanation
          if (correction.explanationFa != null) ...[
            const SizedBox(height: 2),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                correction.explanationFa!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
          ],
          const Divider(),
        ],
      ),
    );
  }
}

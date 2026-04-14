import 'package:flutter/material.dart';
import '../services/llm_backend.dart';

class ModelStatusIndicator extends StatelessWidget {
  const ModelStatusIndicator({
    super.key,
    required this.status,
    this.modelName,
  });

  final BackendStatus? status;
  final String? modelName;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return _buildChip(context,
          icon: Icons.hourglass_empty, label: 'Loading...', color: Colors.grey);
    }

    if (!status!.isReady) {
      return Tooltip(
        message: status!.error ?? 'Backend not ready',
        child: _buildChip(context,
            icon: Icons.error_outline, label: 'Offline', color: Colors.red),
      );
    }

    // Warning state: backend works but with issues (e.g. fell back to Ollama)
    if (status!.error != null) {
      final label = _truncate(
          status!.modelName ?? modelName?.split('/').last ?? 'Warning');
      return Tooltip(
        message: status!.error!,
        child: _buildChip(context,
            icon: Icons.warning_amber_rounded, label: label, color: Colors.orange),
      );
    }

    // Healthy
    final label = _truncate(
        status!.modelName ?? modelName?.split('/').last ?? 'Connected');
    return _buildChip(context,
        icon: Icons.check_circle_outline, label: label, color: Colors.green);
  }

  String _truncate(String s) {
    final clean = s.split('/').last.split('\\').last;
    return clean.length > 20 ? '${clean.substring(0, 17)}...' : clean;
  }

  Widget _buildChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

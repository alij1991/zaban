// Data models for HuggingFace Hub API responses.

class HFModelInfo {
  const HFModelInfo({
    required this.id,
    required this.author,
    this.description,
    this.downloads = 0,
    this.likes = 0,
    this.tags = const [],
    this.lastModified,
    this.isGated = false,
  });

  /// Repo ID, e.g. "unsloth/Qwen3.5-9B-GGUF"
  final String id;
  final String author;
  final String? description;
  final int downloads;
  final int likes;
  final List<String> tags;
  final String? lastModified;
  final bool isGated;

  String get displayName => id.split('/').last;

  String get downloadsFormatted {
    if (downloads >= 1000000) return '${(downloads / 1000000).toStringAsFixed(1)}M';
    if (downloads >= 1000) return '${(downloads / 1000).toStringAsFixed(1)}K';
    return '$downloads';
  }

  factory HFModelInfo.fromJson(Map<String, dynamic> json) => HFModelInfo(
    id: json['id'] as String? ?? json['modelId'] as String? ?? '',
    author: json['author'] as String? ?? '',
    description: json['description'] as String?,
    downloads: json['downloads'] as int? ?? 0,
    likes: json['likes'] as int? ?? 0,
    tags: (json['tags'] as List?)?.cast<String>() ?? [],
    lastModified: json['lastModified'] as String?,
    isGated: json['gated'] == true || json['gated'] == 'auto',
  );
}

class HFModelFile {
  const HFModelFile({
    required this.path,
    required this.size,
    this.isLfs = false,
  });

  /// Filename/path within the repo, e.g. "Qwen3.5-9B-Q4_K_M.gguf"
  final String path;

  /// File size in bytes
  final int size;

  /// Whether the file is stored in Git LFS (most large models are)
  final bool isLfs;

  String get filename => path.split('/').last;

  String get sizeFormatted {
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (size >= 1024) {
      return '${(size / 1024).toStringAsFixed(0)} KB';
    }
    return '$size B';
  }

  /// The quantization level extracted from filename (e.g., "Q4_K_M" from "model-Q4_K_M.gguf")
  String? get quantization {
    final match = RegExp(r'[Qq](\d+[_\w]*)').firstMatch(filename);
    return match?.group(0);
  }

  factory HFModelFile.fromJson(Map<String, dynamic> json) {
    final lfs = json['lfs'] as Map<String, dynamic>?;
    return HFModelFile(
      path: json['path'] as String? ?? '',
      size: lfs?['size'] as int? ?? json['size'] as int? ?? 0,
      isLfs: lfs != null,
    );
  }
}

/// Tracks state of an active download.
class DownloadProgress {
  const DownloadProgress({
    required this.modelId,
    required this.filename,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.state,
    this.localPath,
    this.error,
  });

  final String modelId;
  final String filename;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadState state;
  final String? localPath;
  final String? error;

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';

  String get downloadedFormatted {
    final gb = downloadedBytes / (1024 * 1024 * 1024);
    final totalGb = totalBytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} / ${totalGb.toStringAsFixed(1)} GB';
  }
}

enum DownloadState { pending, downloading, paused, completed, failed, cancelled }

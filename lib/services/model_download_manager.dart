import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/hf_model.dart';
import 'huggingface_service.dart';

/// Manages downloading, storing, and listing local model files.
///
/// Downloads go to `{appSupportDir}/models/{repoId}/`.
/// Supports resumable downloads via HTTP Range headers.
class ModelDownloadManager {
  ModelDownloadManager({required this.hfService});

  final HuggingFaceService hfService;
  final _client = http.Client();

  String? _modelsDir;
  final Map<String, _ActiveDownload> _activeDownloads = {};

  /// Progress stream for the UI.
  final _progressController = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Initialize the models directory.
  Future<String> get modelsDir async {
    if (_modelsDir != null) return _modelsDir!;
    final appDir = await getApplicationSupportDirectory();
    _modelsDir = p.join(appDir.path, 'models');
    await Directory(_modelsDir!).create(recursive: true);
    return _modelsDir!;
  }

  /// List all downloaded model files organized by extension.
  Future<List<LocalModel>> listLocalModels() async {
    final dir = await modelsDir;
    final models = <LocalModel>[];

    await for (final entity in Directory(dir).list(recursive: true)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (['.gguf', '.task', '.bin', '.tflite'].contains(ext)) {
          final stat = await entity.stat();
          models.add(LocalModel(
            path: entity.path,
            filename: p.basename(entity.path),
            size: stat.size,
            modified: stat.modified,
          ));
        }
      }
    }

    models.sort((a, b) => b.modified.compareTo(a.modified));
    return models;
  }

  /// Start downloading a model file from HuggingFace.
  ///
  /// Returns the final local path on success.
  /// Emits [DownloadProgress] updates via [progressStream].
  Future<String> download({
    required String repoId,
    required HFModelFile file,
  }) async {
    final downloadId = '$repoId/${file.filename}';

    // Prepare local directory
    final dir = await modelsDir;
    final safeRepoName = repoId.replaceAll('/', '_');
    final repoDir = p.join(dir, safeRepoName);
    await Directory(repoDir).create(recursive: true);
    final localPath = p.join(repoDir, file.filename);
    final tempPath = '$localPath.part';

    // Check for existing partial download (for resume)
    int existingBytes = 0;
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }

    // If already fully downloaded, return immediately
    final localFile = File(localPath);
    if (await localFile.exists() && await localFile.length() == file.size) {
      _emitProgress(downloadId, file, file.size, file.size, DownloadState.completed, localPath);
      return localPath;
    }

    // Build download URL
    final url = hfService.getDownloadUrl(repoId, file.path);

    // Start download with resume support
    final request = http.Request('GET', Uri.parse(url));
    if (existingBytes > 0) {
      request.headers['Range'] = 'bytes=$existingBytes-';
    }

    final completer = Completer<String>();
    final activeDownload = _ActiveDownload(completer: completer);
    _activeDownloads[downloadId] = activeDownload;

    _emitProgress(downloadId, file, file.size, existingBytes, DownloadState.downloading, null);

    try {
      final response = await _client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      // Open file for writing (append if resuming)
      final sink = tempFile.openWrite(mode: existingBytes > 0 ? FileMode.append : FileMode.write);
      int downloaded = existingBytes;

      await for (final chunk in response.stream) {
        if (activeDownload.isCancelled) {
          await sink.close();
          _emitProgress(downloadId, file, file.size, downloaded, DownloadState.cancelled, null);
          completer.complete(tempPath);
          return tempPath;
        }

        sink.add(chunk);
        downloaded += chunk.length;

        // Emit progress every ~100KB to avoid flooding the stream
        if (downloaded - existingBytes == chunk.length ||
            downloaded % (100 * 1024) < chunk.length) {
          _emitProgress(downloadId, file, file.size, downloaded, DownloadState.downloading, null);
        }
      }

      await sink.flush();
      await sink.close();

      // Rename temp file to final path
      await tempFile.rename(localPath);

      _emitProgress(downloadId, file, file.size, file.size, DownloadState.completed, localPath);
      _activeDownloads.remove(downloadId);
      completer.complete(localPath);
      return localPath;
    } catch (e) {
      _emitProgress(downloadId, file, file.size, existingBytes, DownloadState.failed, null, error: e.toString());
      _activeDownloads.remove(downloadId);
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    }
  }

  /// Cancel an active download.
  void cancelDownload(String repoId, String filename) {
    final downloadId = '$repoId/$filename';
    _activeDownloads[downloadId]?.isCancelled = true;
  }

  /// Check if a specific download is active.
  bool isDownloading(String repoId, String filename) {
    final downloadId = '$repoId/$filename';
    return _activeDownloads.containsKey(downloadId);
  }

  /// Delete a local model file.
  Future<void> deleteModel(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    // Also delete .part file if exists
    final partFile = File('$path.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }

  void _emitProgress(
    String downloadId,
    HFModelFile file,
    int totalBytes,
    int downloadedBytes,
    DownloadState state,
    String? localPath, {
    String? error,
  }) {
    _progressController.add(DownloadProgress(
      modelId: downloadId,
      filename: file.filename,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      state: state,
      localPath: localPath,
      error: error,
    ));
  }

  void dispose() {
    _client.close();
    _progressController.close();
  }
}

class _ActiveDownload {
  _ActiveDownload({required this.completer});
  final Completer<String> completer;
  bool isCancelled = false;
}

class LocalModel {
  const LocalModel({
    required this.path,
    required this.filename,
    required this.size,
    required this.modified,
  });

  final String path;
  final String filename;
  final int size;
  final DateTime modified;

  String get sizeFormatted {
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(size / 1024).toStringAsFixed(0)} KB';
  }

  bool get isGGUF => filename.toLowerCase().endsWith('.gguf');
  bool get isGemma =>
      filename.toLowerCase().endsWith('.task') ||
      filename.toLowerCase().endsWith('.bin') ||
      filename.toLowerCase().endsWith('.tflite');
}

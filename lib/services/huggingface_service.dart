import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/hf_model.dart';

/// HuggingFace Hub API service for searching and listing model files.
///
/// All search/list endpoints are public (no token needed).
/// Download URLs support optional token for gated models.
class HuggingFaceService {
  HuggingFaceService({this.token});

  static const _baseApi = 'https://huggingface.co/api';
  static const _baseUrl = 'https://huggingface.co';

  /// Optional HuggingFace token for gated models and higher rate limits.
  String? token;

  final _client = http.Client();

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Search for models on HuggingFace Hub.
  ///
  /// [query] — search term (e.g., "qwen 9b gguf")
  /// [sort] — sort by: "downloads", "likes", "trending_score", "last_modified"
  /// [limit] — max results (default 20)
  Future<List<HFModelInfo>> searchModels({
    required String query,
    String sort = 'downloads',
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseApi/models').replace(
      queryParameters: {
        'search': query,
        'sort': sort,
        'direction': '-1',
        'limit': '$limit',
      },
    );

    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HuggingFace search failed: ${response.statusCode}');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((item) => HFModelInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// List files in a HuggingFace model repository.
  ///
  /// [repoId] — e.g., "unsloth/Qwen3.5-9B-GGUF"
  /// [extensions] — filter for specific extensions (e.g., ['.gguf'])
  Future<List<HFModelFile>> listFiles({
    required String repoId,
    List<String> extensions = const [],
  }) async {
    final uri = Uri.parse('$_baseApi/models/$repoId/tree/main');

    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      throw Exception('Repository not found: $repoId');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to list files: ${response.statusCode}');
    }

    final List<dynamic> data = jsonDecode(response.body);
    var files = data
        .where((item) => item['type'] == 'file')
        .map((item) => HFModelFile.fromJson(item as Map<String, dynamic>))
        .toList();

    // Filter by extensions
    if (extensions.isNotEmpty) {
      files = files.where((f) {
        final lower = f.path.toLowerCase();
        return extensions.any((ext) => lower.endsWith(ext));
      }).toList();
    }

    // Sort by size descending (largest quantizations first)
    files.sort((a, b) => b.size.compareTo(a.size));

    return files;
  }

  /// Get the direct download URL for a file.
  String getDownloadUrl(String repoId, String filename) {
    final url = '$_baseUrl/$repoId/resolve/main/$filename';
    if (token != null) return '$url?token=$token';
    return url;
  }

  void dispose() {
    _client.close();
  }
}

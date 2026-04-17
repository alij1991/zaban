import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:http/http.dart' as http;
import '../models/hardware_tier.dart';
import '../models/llm_model_catalog.dart';
import '../models/user_profile.dart';
import '../models/cefr_level.dart';
import '../services/database_service.dart';
import '../services/hardware_detection_service.dart';
import '../services/llm_service.dart';
import '../services/llm_backend.dart';
import '../services/llm_backend_factory.dart';
import '../services/llm_backend_ollama.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({required this.db});

  final DatabaseService db;

  UserProfile _profile = UserProfile();
  UserProfile get profile => _profile;

  HardwareDetectionResult? _hardware;
  HardwareDetectionResult? get hardware => _hardware;

  BackendStatus? _backendStatus;
  BackendStatus? get backendStatus => _backendStatus;

  late LLMService _llmService;
  LLMService get llmService => _llmService;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _profile = await db.getUserProfile();

    // Auto-detect hardware if not set
    if (_profile.hardwareTier == null) {
      _hardware = await HardwareDetectionService.detect();
      _profile.hardwareTier = _hardware!.tier;
      // RAM-aware default: pick the biggest catalog model that fits current
      // total RAM (Qwen3-4B if ≥ 8 GB, Qwen3-1.7B if ≥ 4 GB, Gemma3:1b
      // otherwise). Falls back to the VRAM-tier recommendation if RAM
      // detection failed — never nothing.
      final picked = LlmModelCatalog.pickForRam(_hardware!.systemRamGb);
      _profile.selectedModel = picked.ollamaTag;
      debugPrint(
        'First-run model pick: ${picked.displayName} (${picked.ollamaTag}) '
        '— total RAM: ${_hardware!.systemRamGb?.toStringAsFixed(1) ?? "unknown"} GB, '
        'threshold: ${picked.minRamGb} GB, VRAM tier: ${_hardware!.tier.name}',
      );
      await db.saveUserProfile(_profile);
    }

    // ALWAYS validate Ollama model so we have a working fallback ready
    await _validateOllamaModel();

    // Create backend from user's selected type
    final backend = LLMBackendFactory.createFromProfile(_profile);
    _llmService = LLMService(backend: backend);

    // Try to initialize the backend
    String? initError;
    try {
      await backend.initialize();
    } catch (e) {
      initError = e.toString();
      debugPrint('Backend init failed: $e');
    }

    // Check if backend is actually working
    _backendStatus = await _llmService.checkStatus();

    // If primary backend failed → auto-fallback to Ollama
    if (initError != null || !(_backendStatus?.isReady ?? false)) {
      if (_profile.backendType != BackendType.ollama) {
        debugPrint('Primary backend ${_profile.backendType.name} failed. '
            'Falling back to Ollama.');
        await _fallbackToOllama(
          originalError: initError ?? _backendStatus?.error,
        );
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateProfile(UserProfile profile) async {
    _profile = profile;
    await db.saveUserProfile(profile);
    notifyListeners();
  }

  Future<void> setCEFRLevel(CEFRLevel level) async {
    _profile.cefrLevel = level;
    await db.saveUserProfile(_profile);
    notifyListeners();
  }

  /// Switch to a different LLM backend type.
  Future<void> switchBackend(BackendType type) async {
    _profile.backendType = type;
    await db.saveUserProfile(_profile);

    // When switching TO Direct GGUF or Gemma, unload Ollama's model
    // to free RAM for the new backend's model loading.
    if (type == BackendType.directFfi || type == BackendType.gemma) {
      await _unloadOllamaModel();
    }

    final newBackend = LLMBackendFactory.createFromProfile(_profile);
    try {
      await _llmService.switchBackend(newBackend);
    } catch (e) {
      debugPrint('Backend switch failed: $e');
    }

    _backendStatus = await _llmService.checkStatus();
    notifyListeners();
  }

  /// Tell Ollama to unload its model from memory to free RAM.
  Future<void> _unloadOllamaModel() async {
    try {
      // Use the top-level http.post() — it manages its own connection and
      // does not leak a client, unlike http.Client().post() which requires
      // an explicit .close() call.
      await http
          .post(
            Uri.parse('${_profile.ollamaHost}/api/generate'),
            body: '{"model":"_","keep_alive":0}',
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> setModel(String model) async {
    _profile.selectedModel = model;
    await db.saveUserProfile(_profile);
    if (_profile.backendType == BackendType.ollama) {
      await switchBackend(BackendType.ollama);
    }
  }

  Future<void> setGGUFPath(String path) async {
    _profile.ggufModelPath = path;
    await db.saveUserProfile(_profile);
    if (_profile.backendType == BackendType.directFfi) {
      await switchBackend(BackendType.directFfi);
    }
    notifyListeners();
  }

  Future<void> setGemmaModelPath(String path) async {
    _profile.gemmaModelPath = path;
    await db.saveUserProfile(_profile);
    if (_profile.backendType == BackendType.gemma) {
      await switchBackend(BackendType.gemma);
    }
    notifyListeners();
  }

  Future<void> setHardwareTier(HardwareTier tier) async {
    _profile.hardwareTier = tier;
    // Apply the same RAM-aware pick we use on first run so that re-detecting
    // hardware doesn't regress the model choice back to something that won't
    // fit. If no RAM reading exists yet (user changed tier manually without
    // running detection), trigger detection so we have a number to pick from.
    _hardware ??= await HardwareDetectionService.detect();
    final picked = LlmModelCatalog.pickForRam(_hardware?.systemRamGb);
    _profile.selectedModel = picked.ollamaTag;
    debugPrint(
      'Tier change → model pick: ${picked.displayName} (${picked.ollamaTag}) '
      '— total RAM: ${_hardware?.systemRamGb?.toStringAsFixed(1) ?? "unknown"} GB',
    );
    await db.saveUserProfile(_profile);
    if (_profile.backendType == BackendType.ollama) {
      await switchBackend(BackendType.ollama);
    }
    notifyListeners();
  }

  Future<void> refreshBackendStatus() async {
    _backendStatus = await _llmService.checkStatus();
    notifyListeners();
  }

  Future<void> detectHardware() async {
    _hardware = await HardwareDetectionService.detect();
    notifyListeners();
  }

  /// Flutter ThemeMode derived from the persisted string preference.
  ThemeMode get themeMode => switch (_profile.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Persist a new theme mode ('light', 'dark', or 'system').
  Future<void> setThemeMode(String mode) async {
    _profile.themeMode = mode;
    await db.saveUserProfile(_profile);
    notifyListeners();
  }

  /// Update the daily streak, applying a streak freeze if the user missed
  /// exactly one day and has a freeze banked.
  ///
  /// Streak freeze rules (research-backed: single highest-ROI retention feature):
  ///   • 1 freeze is available by default.
  ///   • A freeze is consumed automatically when the user misses 1 day.
  ///   • After 7 consecutive active days the freeze refills (max 1).
  ///   • Missing > 1 day: streak resets even if a freeze is available.
  Future<void> updateStreak() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Reset the "used today" flag at the start of a new day
    _profile.streakFreezeUsedToday = false;

    if (_profile.lastActiveDate != null) {
      final lastActive = DateTime(
        _profile.lastActiveDate!.year,
        _profile.lastActiveDate!.month,
        _profile.lastActiveDate!.day,
      );
      final diff = today.difference(lastActive).inDays;

      if (diff == 0) {
        // Already checked in today — no change needed
      } else if (diff == 1) {
        // Perfect streak continuation
        _profile.currentStreak++;
      } else if (diff == 2 && _profile.streakFreezeAvailable > 0) {
        // Missed exactly 1 day — use freeze to protect streak
        _profile.currentStreak++;
        _profile.streakFreezeAvailable =
            (_profile.streakFreezeAvailable - 1).clamp(0, 1);
        _profile.streakFreezeUsedToday = true;
        debugPrint('Streak freeze consumed — streak protected at '
            '${_profile.currentStreak} days');
      } else if (diff > 1) {
        // Too many days missed — reset streak
        _profile.currentStreak = 1;
      }
    } else {
      _profile.currentStreak = 1;
    }

    if (_profile.currentStreak > _profile.longestStreak) {
      _profile.longestStreak = _profile.currentStreak;
    }

    // Refill freeze after 7 consecutive active days (max 1)
    if (_profile.currentStreak > 0 &&
        _profile.currentStreak % 7 == 0 &&
        _profile.streakFreezeAvailable == 0) {
      _profile.streakFreezeAvailable = 1;
      debugPrint('Streak freeze refilled at ${_profile.currentStreak}-day streak');
    }

    _profile.lastActiveDate = now;
    await db.saveUserProfile(_profile);
    notifyListeners();
  }

  /// When the primary backend fails, fall back to Ollama with the best
  /// available model. This ensures the app is always functional if Ollama
  /// is running, regardless of which backend the user selected.
  Future<void> _fallbackToOllama({String? originalError}) async {
    try {
      final response = await http
          .get(Uri.parse('${_profile.ollamaHost}/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['models'] as List?)
              ?.map((m) => m['name'] as String)
              .toList() ??
          [];
      if (models.isEmpty) return;

      // Pick the SMALLEST available chat model for fallback to minimize RAM usage.
      // This leaves room for the user to switch to Direct GGUF later.
      final chatModels = models
          .where((m) => !m.contains('embed') && !m.contains('nomic'))
          .toList();
      // Prefer small models: look for 1b, 2b, 4b variants first
      final small = chatModels.where((m) =>
          m.contains('1b') || m.contains('2b') || m.contains(':4b')).toList();
      final best = small.isNotEmpty
          ? small.first
          : (chatModels.isNotEmpty ? chatModels.last : models.first);

      // Create Ollama backend and switch to it
      final ollamaBackend = OllamaBackend(
        host: _profile.ollamaHost,
        model: best,
      );
      await ollamaBackend.initialize();
      _llmService = LLMService(backend: ollamaBackend);
      _backendStatus = await _llmService.checkStatus();

      // Show warning that we fell back
      if (_backendStatus != null && _backendStatus!.isReady) {
        _backendStatus = BackendStatus(
          isReady: true,
          modelName: best,
          backendType: BackendType.ollama,
          availableModels: _backendStatus!.availableModels,
          error: 'Using Ollama ($best) — '
              '${_profile.backendType.name} backend failed: '
              '${originalError ?? "unknown error"}',
        );
      }
      debugPrint('Fell back to Ollama with model: $best');
    } catch (e) {
      debugPrint('Ollama fallback also failed: $e');
    }
  }

  /// Check if the selected Ollama model exists. If not, auto-select
  /// the first available chat model.
  Future<void> _validateOllamaModel() async {
    try {
      final response = await http
          .get(Uri.parse('${_profile.ollamaHost}/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (data['models'] as List?)
              ?.map((m) => m['name'] as String)
              .toList() ??
          [];
      if (models.isEmpty) return;

      final selected = _profile.selectedModel ?? '';
      final exists = models.any(
          (m) => m == selected || m.startsWith(selected) || selected.contains(m));

      if (!exists) {
        final chatModels = models
            .where((m) => !m.contains('embed') && !m.contains('nomic'))
            .toList();
        final best = chatModels.isNotEmpty ? chatModels.first : models.first;
        debugPrint('Ollama: "$selected" not found. Using "$best"');
        _profile.selectedModel = best;
        await db.saveUserProfile(_profile);
      }
    } catch (e) {
      debugPrint('Ollama model validation failed: $e');
    }
  }
}

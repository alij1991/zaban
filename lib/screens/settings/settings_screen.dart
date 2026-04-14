import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/cefr_level.dart';
import '../../models/hardware_tier.dart';
import '../../models/hf_model.dart';
import '../../models/user_profile.dart';
import '../../providers/settings_provider.dart';
import '../../services/llm_backend.dart';
import '../../services/huggingface_service.dart';
import '../../services/model_download_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _nameFaController = TextEditingController();
  final _ollamaHostController = TextEditingController();
  final _ggufPathController = TextEditingController();
  final _gemmaPathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = context.read<SettingsProvider>().profile;
    _nameController.text = profile.name ?? '';
    _nameFaController.text = profile.nameFa ?? '';
    _ollamaHostController.text = profile.ollamaHost;
    _ggufPathController.text = profile.ggufModelPath ?? '';
    _gemmaPathController.text = profile.gemmaModelPath ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFaController.dispose();
    _ollamaHostController.dispose();
    _ggufPathController.dispose();
    _gemmaPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final profile = settings.profile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'تنظیمات',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Profile section
            _SectionHeader(title: 'Profile', titleFa: 'پروفایل'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name (English)',
                      hintText: 'Your name',
                    ),
                    onChanged: (v) {
                      profile.name = v.isEmpty ? null : v;
                      settings.updateProfile(profile);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: TextField(
                      controller: _nameFaController,
                      decoration: const InputDecoration(
                        labelText: 'نام (فارسی)',
                        hintText: 'نام شما',
                      ),
                      onChanged: (v) {
                        profile.nameFa = v.isEmpty ? null : v;
                        settings.updateProfile(profile);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // CEFR Level
            _SectionHeader(title: 'English Level', titleFa: 'سطح زبان'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CEFRLevel.values.map(
                (level) => ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(level.code),
                      const SizedBox(width: 4),
                      Text(level.nameEn, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  selected: profile.cefrLevel == level,
                  onSelected: (_) => settings.setCEFRLevel(level),
                ),
              ).toList(),
            ),
            const SizedBox(height: 24),

            // Learning goal
            _SectionHeader(title: 'Learning Goal', titleFa: 'هدف یادگیری'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: LearningGoal.values.map(
                (goal) => ChoiceChip(
                  label: Text(goal.nameEn),
                  selected: profile.learningGoal == goal,
                  onSelected: (_) {
                    profile.learningGoal = goal;
                    settings.updateProfile(profile);
                  },
                ),
              ).toList(),
            ),
            const SizedBox(height: 24),

            // Preferences
            _SectionHeader(title: 'Preferences', titleFa: 'ترجیحات'),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Show Persian translations'),
              subtitle: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('نمایش ترجمه فارسی',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(150))),
              ),
              value: profile.showTranslations,
              onChanged: (v) {
                profile.showTranslations = v;
                settings.updateProfile(profile);
              },
            ),
            SwitchListTile(
              title: const Text('Prefer Finglish input'),
              subtitle: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('ورودی فینگلیش',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(150))),
              ),
              value: profile.preferFinglish,
              onChanged: (v) {
                profile.preferFinglish = v;
                settings.updateProfile(profile);
              },
            ),
            const SizedBox(height: 24),

            // === AI MODEL SECTION ===
            _SectionHeader(title: 'AI Model Backend', titleFa: 'موتور مدل هوش مصنوعی'),
            const SizedBox(height: 12),

            // Hardware detection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.memory, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hardware: ${settings.hardware?.summary ?? "Not detected"}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => settings.detectHardware(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Detect'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Backend type selector
            SegmentedButton<BackendType>(
              segments: const [
                ButtonSegment(
                  value: BackendType.ollama,
                  label: Text('Ollama Server'),
                  icon: Icon(Icons.cloud_outlined),
                ),
                ButtonSegment(
                  value: BackendType.directFfi,
                  label: Text('Direct GGUF'),
                  icon: Icon(Icons.bolt),
                ),
                ButtonSegment(
                  value: BackendType.gemma,
                  label: Text('Gemma (LiteRT)'),
                  icon: Icon(Icons.auto_awesome),
                ),
              ],
              selected: {profile.backendType},
              onSelectionChanged: (selected) {
                settings.switchBackend(selected.first);
              },
            ),
            const SizedBox(height: 12),

            // Backend status indicator
            _BackendStatusCard(status: settings.backendStatus),
            const SizedBox(height: 12),

            // Backend-specific configuration
            if (profile.backendType == BackendType.ollama)
              _OllamaPanel(
                settings: settings,
                profile: profile,
                hostController: _ollamaHostController,
              ),
            if (profile.backendType == BackendType.directFfi)
              _DirectFFIPanel(
                settings: settings,
                profile: profile,
                pathController: _ggufPathController,
              ),
            if (profile.backendType == BackendType.gemma)
              _GemmaPanel(
                settings: settings,
                profile: profile,
                pathController: _gemmaPathController,
              ),

            const SizedBox(height: 32),

            // About
            _SectionHeader(title: 'About', titleFa: 'درباره'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Zaban — AI English Tutor for Persian Speakers',
                        style: Theme.of(context).textTheme.titleSmall),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        'زبان — معلم هوش مصنوعی انگلیسی برای فارسی‌زبانان',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Version 1.0.0\n'
                      'Fully offline — your data stays on your device.\n'
                      'Supports: Ollama, Direct GGUF (llama.cpp), Gemma (LiteRT)',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === Backend Status Card ===

class _BackendStatusCard extends StatelessWidget {
  const _BackendStatusCard({required this.status});
  final BackendStatus? status;

  @override
  Widget build(BuildContext context) {
    final isReady = status?.isReady ?? false;
    final color = isReady ? Colors.green : Colors.orange;
    final icon = isReady ? Icons.check_circle : Icons.warning_amber_rounded;
    final label = isReady
        ? 'Connected: ${status?.modelName ?? "Ready"}'
        : status?.error ?? 'Not connected';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// === Ollama Panel ===

class _OllamaPanel extends StatelessWidget {
  const _OllamaPanel({
    required this.settings,
    required this.profile,
    required this.hostController,
  });

  final SettingsProvider settings;
  final UserProfile profile;
  final TextEditingController hostController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ollama Configuration',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Ollama Host',
                hintText: 'http://localhost:11434',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (v) {
                profile.ollamaHost = v;
                settings.updateProfile(profile);
                settings.switchBackend(BackendType.ollama);
              },
            ),
            const SizedBox(height: 12),
            // Hardware tier selector
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: HardwareTier.values.map(
                (tier) => ChoiceChip(
                  label: Text(tier.label, style: const TextStyle(fontSize: 12)),
                  selected: profile.hardwareTier == tier,
                  onSelected: (_) => settings.setHardwareTier(tier),
                  visualDensity: VisualDensity.compact,
                ),
              ).toList(),
            ),
            if (settings.backendStatus?.availableModels.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text('Available models:', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: settings.backendStatus!.availableModels.map(
                  (model) => ActionChip(
                    label: Text(model, style: const TextStyle(fontSize: 11)),
                    onPressed: () => settings.setModel(model),
                    backgroundColor: profile.selectedModel == model
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                ).toList(),
              ),
            ],
            if (settings.backendStatus?.isReady == false) ...[
              const SizedBox(height: 12),
              _TerminalHelp(commands: [
                ('Start Ollama:', 'ollama serve'),
                ('Pull a model:', 'ollama pull ${profile.hardwareTier?.recommendedModel ?? "qwen3.5:9b"}'),
              ]),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => settings.refreshBackendStatus(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Test Connection'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === Direct FFI Panel ===

class _DirectFFIPanel extends StatelessWidget {
  const _DirectFFIPanel({
    required this.settings,
    required this.profile,
    required this.pathController,
  });

  final SettingsProvider settings;
  final UserProfile profile;
  final TextEditingController pathController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Direct GGUF Configuration',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('~15-25% faster',
                      style: TextStyle(fontSize: 10, color: Colors.blue)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Runs the model in-process via llama.cpp — no Ollama server needed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              ),
            ),
            const SizedBox(height: 12),

            // GGUF file path
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pathController,
                    decoration: const InputDecoration(
                      labelText: 'GGUF Model File',
                      hintText: 'C:\\Models\\Qwen3.5-9B-Q4_K_M.gguf',
                      prefixIcon: Icon(Icons.file_present),
                    ),
                    onSubmitted: (v) => settings.setGGUFPath(v),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['gguf'],
                      dialogTitle: 'Select GGUF Model File',
                    );
                    if (result != null && result.files.single.path != null) {
                      pathController.text = result.files.single.path!;
                      settings.setGGUFPath(result.files.single.path!);
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // GPU Layers slider
            Row(
              children: [
                Text('GPU Layers: ', style: Theme.of(context).textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: profile.gpuLayers.toDouble().clamp(0, 999),
                    min: 0,
                    max: 999,
                    divisions: 20,
                    label: profile.gpuLayers == 999 ? 'All' : '${profile.gpuLayers}',
                    onChanged: (v) {
                      profile.gpuLayers = v.round();
                      settings.updateProfile(profile);
                    },
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    profile.gpuLayers == 999 ? 'All' : '${profile.gpuLayers}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            Text(
              'Set to "All" to load the entire model on GPU. Reduce if you run out of VRAM.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
            ),
            const SizedBox(height: 12),

            // Context size
            Row(
              children: [
                Text('Context Size: ', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2048, label: Text('2K')),
                    ButtonSegment(value: 4096, label: Text('4K')),
                    ButtonSegment(value: 8192, label: Text('8K')),
                    ButtonSegment(value: 16384, label: Text('16K')),
                  ],
                  selected: {profile.contextSize},
                  onSelectionChanged: (s) {
                    profile.contextSize = s.first;
                    settings.updateProfile(profile);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            const SizedBox(height: 16),
            _ModelDownloadSection(
              fileExtensions: const ['.gguf'],
              searchHint: 'Search GGUF models (e.g., "qwen 9b gguf")',
              onModelSelected: (path) {
                pathController.text = path;
                settings.setGGUFPath(path);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// === Gemma Panel ===

class _GemmaPanel extends StatelessWidget {
  const _GemmaPanel({
    required this.settings,
    required this.profile,
    required this.pathController,
  });

  final SettingsProvider settings;
  final UserProfile profile;
  final TextEditingController pathController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gemma (LiteRT) Configuration',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Uses Google MediaPipe LiteRT for optimized Gemma model inference.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
              ),
            ),
            const SizedBox(height: 12),

            // Model file path
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pathController,
                    decoration: const InputDecoration(
                      labelText: 'Gemma Model File',
                      hintText: 'C:\\Models\\gemma-4-e4b.litertlm',
                      prefixIcon: Icon(Icons.file_present),
                    ),
                    onSubmitted: (v) => settings.setGemmaModelPath(v),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['litertlm', 'task', 'bin'],
                      dialogTitle: 'Select Gemma Model File',
                    );
                    if (result != null && result.files.single.path != null) {
                      pathController.text = result.files.single.path!;
                      settings.setGemmaModelPath(result.files.single.path!);
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Context size
            Row(
              children: [
                Text('Context Size: ', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 2048, label: Text('2K')),
                    ButtonSegment(value: 4096, label: Text('4K')),
                    ButtonSegment(value: 8192, label: Text('8K')),
                  ],
                  selected: {profile.contextSize.clamp(2048, 8192)},
                  onSelectionChanged: (s) {
                    profile.contextSize = s.first;
                    settings.updateProfile(profile);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            Text(
              'Supported formats: .litertlm (recommended for desktop), .task (mobile), .bin',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
            ),

            const SizedBox(height: 16),
            _ModelDownloadSection(
              fileExtensions: const ['.litertlm', '.task', '.bin'],
              searchHint: 'Search Gemma models (e.g., "gemma 4 litert")',
              onModelSelected: (path) {
                pathController.text = path;
                settings.setGemmaModelPath(path);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// === Shared Widgets ===

class _TerminalHelp extends StatelessWidget {
  const _TerminalHelp({required this.commands});
  final List<(String label, String command)> commands;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: commands.map((c) {
          if (c.$2.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(c.$1, style: const TextStyle(fontSize: 13)),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.$1, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    c.$2,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      color: Colors.greenAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// === Model Download Section ===

class _ModelDownloadSection extends StatefulWidget {
  const _ModelDownloadSection({
    required this.fileExtensions,
    required this.searchHint,
    required this.onModelSelected,
  });

  final List<String> fileExtensions;
  final String searchHint;
  final void Function(String localPath) onModelSelected;

  @override
  State<_ModelDownloadSection> createState() => _ModelDownloadSectionState();
}

class _ModelDownloadSectionState extends State<_ModelDownloadSection> {
  final _searchController = TextEditingController();
  final _hfService = HuggingFaceService();
  late final ModelDownloadManager _downloadManager;

  List<HFModelInfo>? _searchResults;
  List<HFModelFile>? _selectedRepoFiles;
  String? _selectedRepoId;
  bool _isSearching = false;
  bool _isLoadingFiles = false;
  DownloadProgress? _currentDownload;
  StreamSubscription<DownloadProgress>? _progressSub;
  List<LocalModel>? _localModels;

  @override
  void initState() {
    super.initState();
    _downloadManager = ModelDownloadManager(hfService: _hfService);
    _progressSub = _downloadManager.progressStream.listen((progress) {
      setState(() => _currentDownload = progress);
      if (progress.state == DownloadState.completed && progress.localPath != null) {
        widget.onModelSelected(progress.localPath!);
        _loadLocalModels();
      }
    });
    _loadLocalModels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _progressSub?.cancel();
    _hfService.dispose();
    _downloadManager.dispose();
    super.dispose();
  }

  Future<void> _loadLocalModels() async {
    final models = await _downloadManager.listLocalModels();
    setState(() {
      _localModels = models.where((m) {
        final lower = m.filename.toLowerCase();
        return widget.fileExtensions.any((ext) => lower.endsWith(ext));
      }).toList();
    });
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults = null;
      _selectedRepoFiles = null;
      _selectedRepoId = null;
    });

    try {
      final results = await _hfService.searchModels(query: query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }

  Future<void> _selectRepo(String repoId) async {
    setState(() {
      _isLoadingFiles = true;
      _selectedRepoId = repoId;
      _selectedRepoFiles = null;
    });

    try {
      final files = await _hfService.listFiles(
        repoId: repoId,
        extensions: widget.fileExtensions,
      );
      setState(() {
        _selectedRepoFiles = files;
        _isLoadingFiles = false;
      });
    } catch (e) {
      setState(() => _isLoadingFiles = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to list files: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(HFModelFile file) async {
    if (_selectedRepoId == null) return;
    try {
      await _downloadManager.download(
        repoId: _selectedRepoId!,
        file: file,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Local models
        if (_localModels != null && _localModels!.isNotEmpty) ...[
          Text('Downloaded Models', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          ..._localModels!.map((m) => Card(
            child: ListTile(
              leading: Icon(
                m.isGGUF ? Icons.bolt : Icons.auto_awesome,
                color: theme.colorScheme.primary,
              ),
              title: Text(m.filename, style: const TextStyle(fontSize: 13)),
              subtitle: Text(m.sizeFormatted),
              trailing: TextButton(
                onPressed: () => widget.onModelSelected(m.path),
                child: const Text('Use'),
              ),
              dense: true,
            ),
          )),
          const SizedBox(height: 12),
        ],

        // Recommended models
        _RecommendedModels(
          extensions: widget.fileExtensions,
          onTapRepo: _selectRepo,
        ),
        const SizedBox(height: 16),

        // Download section header
        Row(
          children: [
            const Icon(Icons.search, size: 18),
            const SizedBox(width: 6),
            Text('Search HuggingFace', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),

        // Search bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSearching ? null : _search,
              child: _isSearching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Search'),
            ),
          ],
        ),

        // Active download progress
        if (_currentDownload != null &&
            (_currentDownload!.state == DownloadState.downloading ||
             _currentDownload!.state == DownloadState.pending)) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Downloading ${_currentDownload!.filename}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final parts = _currentDownload!.modelId.split('/');
                          if (parts.length >= 2) {
                            _downloadManager.cancelDownload(
                              '${parts[0]}/${parts[1]}',
                              _currentDownload!.filename,
                            );
                          }
                        },
                        child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _currentDownload!.progress,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_currentDownload!.downloadedFormatted} (${_currentDownload!.progressPercent})',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],

        // Download completed
        if (_currentDownload?.state == DownloadState.completed) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_currentDownload!.filename} downloaded and activated!',
                      style: const TextStyle(fontSize: 13, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Search results
        if (_searchResults != null) ...[
          const SizedBox(height: 12),
          if (_searchResults!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No models found. Try a different search term.'),
            )
          else ...[
            // Show repo list OR file list
            if (_selectedRepoFiles == null) ...[
              Text('${_searchResults!.length} results', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults!.length,
                  itemBuilder: (context, index) {
                    final model = _searchResults![index];
                    return Card(
                      child: ListTile(
                        title: Text(model.id, style: const TextStyle(fontSize: 13)),
                        subtitle: Row(
                          children: [
                            Icon(Icons.download, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(model.downloadsFormatted, style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 12),
                            Icon(Icons.favorite, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('${model.likes}', style: const TextStyle(fontSize: 11)),
                            if (model.isGated) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.lock, size: 12, color: Colors.orange),
                            ],
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        dense: true,
                        onTap: () => _selectRepo(model.id),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              // File list for selected repo
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: () => setState(() {
                      _selectedRepoFiles = null;
                      _selectedRepoId = null;
                    }),
                    tooltip: 'Back to search results',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: Text(
                      _selectedRepoId!,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoadingFiles)
                const Center(child: CircularProgressIndicator())
              else if (_selectedRepoFiles!.isEmpty)
                Text(
                  'No ${widget.fileExtensions.join("/")} files found in this repository.',
                  style: theme.textTheme.bodySmall,
                )
              else
                ...(_selectedRepoFiles!.map(
                  (file) => Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.insert_drive_file,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      title: Text(file.filename, style: const TextStyle(fontSize: 13)),
                      subtitle: Row(
                        children: [
                          Text(file.sizeFormatted, style: const TextStyle(fontSize: 11)),
                          if (file.quantization != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                file.quantization!,
                                style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: ElevatedButton.icon(
                        onPressed: (_currentDownload?.state == DownloadState.downloading)
                            ? null
                            : () => _downloadFile(file),
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      dense: true,
                    ),
                  ),
                )),
            ],
          ],
        ],
      ],
    );
  }
}

// === Recommended Models ===

class _RecommendedModel {
  const _RecommendedModel({
    required this.repoId,
    required this.name,
    required this.size,
    required this.description,
    this.badge,
  });
  final String repoId;
  final String name;
  final String size;
  final String description;
  final String? badge;
}

const _ggufRecommended = [
  _RecommendedModel(
    repoId: 'Qwen/Qwen3-8B-GGUF',
    name: 'Qwen3-8B',
    size: '~5 GB',
    description: 'Best for Persian+English. 100+ languages, strong instruction following.',
    badge: 'Best for Persian',
  ),
  _RecommendedModel(
    repoId: 'unsloth/Qwen3.5-4B-GGUF',
    name: 'Qwen3.5-4B',
    size: '~2.5 GB',
    description: 'Lightweight. Great quality for its size, 201 languages.',
  ),
  _RecommendedModel(
    repoId: 'unsloth/gemma-4-E4B-it-GGUF',
    name: 'Gemma 4 E4B',
    size: '~3 GB',
    description: 'Good all-rounder. 140+ languages, Apache 2.0 license.',
  ),
  _RecommendedModel(
    repoId: 'unsloth/gemma-4-26B-A4B-it-GGUF',
    name: 'Gemma 4 26B-A4B MoE',
    size: '~15 GB',
    description: 'Highest quality. Only 4B active params but 26B total. Needs 16GB+ VRAM.',
    badge: 'Best Quality',
  ),
  _RecommendedModel(
    repoId: 'QuantFactory/PersianMind-v1.0-GGUF',
    name: 'PersianMind v1.0',
    size: '~3.9 GB',
    description: 'Specialized Persian-English model. State-of-the-art on Persian benchmarks.',
    badge: 'Persian Specialist',
  ),
];

const _gemmaRecommended = [
  _RecommendedModel(
    repoId: 'litert-community/gemma-4-E4B-it-litert-lm',
    name: 'Gemma 4 E4B LiteRT-LM',
    size: '~1.5 GB',
    description: 'Optimized for desktop. 140+ languages, fast inference.',
    badge: 'Recommended',
  ),
  _RecommendedModel(
    repoId: 'litert-community/gemma-4-E2B-it-litert-lm',
    name: 'Gemma 4 E2B LiteRT-LM',
    size: '~1 GB',
    description: 'Ultralight. Fits on any hardware, basic conversation quality.',
  ),
  _RecommendedModel(
    repoId: 'google/gemma-3n-E4B-it-litert-lm',
    name: 'Gemma 3n E4B LiteRT-LM',
    size: '~1.5 GB',
    description: 'Gemma 3n variant with audio input support.',
  ),
];

class _RecommendedModels extends StatelessWidget {
  const _RecommendedModels({
    required this.extensions,
    required this.onTapRepo,
  });

  final List<String> extensions;
  final void Function(String repoId) onTapRepo;

  bool get isGGUF => extensions.contains('.gguf');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = isGGUF ? _ggufRecommended : _gemmaRecommended;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star, size: 18, color: Colors.amber),
            const SizedBox(width: 6),
            Text('Recommended Models', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        ...models.map((m) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTapRepo(m.repoId),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isGGUF ? Icons.bolt : Icons.auto_awesome,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(m.name,
                                style: theme.textTheme.titleSmall?.copyWith(fontSize: 13)),
                            const SizedBox(width: 6),
                            Text(m.size,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            if (m.badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.withAlpha(80)),
                                ),
                                child: Text(m.badge!,
                                    style: const TextStyle(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(m.description,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            maxLines: 2),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        )),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.titleFa});
  final String title;
  final String titleFa;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            titleFa,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
          ),
        ),
      ],
    );
  }
}

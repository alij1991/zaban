import 'cefr_level.dart';
import 'hardware_tier.dart';
import '../services/llm_backend.dart';

class UserProfile {
  UserProfile({
    this.name,
    this.nameFa,
    this.cefrLevel = CEFRLevel.a2,
    this.nativeLanguage = 'fa',
    this.learningGoal = LearningGoal.general,
    this.dailyGoalMinutes = 15,
    this.preferFinglish = false,
    this.showTranslations = true,
    this.autoPlayAudio = true,
    this.hardwareTier,
    this.selectedModel,
    this.ollamaHost = 'http://localhost:11434',
    this.backendType = BackendType.ollama,
    this.ggufModelPath,
    this.gemmaModelPath,
    this.gpuLayers = 999,
    this.contextSize = 8192,
    this.huggingFaceToken,
    this.totalConversations = 0,
    this.totalMinutes = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActiveDate,
    this.vocabularyCount = 0,
    // FSRS settings
    this.srsTargetRetention = 0.85,
    this.srsDailyNewLimit = 5,
    // Streak freeze
    this.streakFreezeAvailable = 1,
    this.streakFreezeUsedToday = false,
    // Appearance
    this.themeMode = 'system',
  });

  String? name;
  String? nameFa;
  CEFRLevel cefrLevel;
  String nativeLanguage;
  LearningGoal learningGoal;
  int dailyGoalMinutes;
  bool preferFinglish;
  bool showTranslations;
  bool autoPlayAudio;
  HardwareTier? hardwareTier;
  String? selectedModel;
  String ollamaHost;

  // Backend configuration
  BackendType backendType;
  String? ggufModelPath;     // for DirectLlamaBackend
  String? gemmaModelPath;    // for GemmaBackend
  int gpuLayers;             // for DirectLlamaBackend (0-999)
  int contextSize;           // context window tokens
  String? huggingFaceToken;  // for GemmaBackend model downloads

  // Stats
  int totalConversations;
  int totalMinutes;
  int currentStreak;
  int longestStreak;
  DateTime? lastActiveDate;
  int vocabularyCount;

  // FSRS settings — exposed in Settings so power users can tune
  double srsTargetRetention; // 0.70–0.97, default 0.85 (85 %)
  int srsDailyNewLimit;      // new cards per day, default 5

  // Streak freeze mechanic (research: single highest-ROI engagement feature)
  // One freeze is available by default; refills after 7 consecutive days.
  int streakFreezeAvailable;  // number of freezes banked (0 or 1)
  bool streakFreezeUsedToday; // consumed a freeze in today's update

  // Appearance ('light', 'dark', 'system')
  String themeMode;

  Map<String, dynamic> toMap() => {
    'name': name,
    'name_fa': nameFa,
    'cefr_level': cefrLevel.code,
    'native_language': nativeLanguage,
    'learning_goal': learningGoal.name,
    'daily_goal_minutes': dailyGoalMinutes,
    'prefer_finglish': preferFinglish ? 1 : 0,
    'show_translations': showTranslations ? 1 : 0,
    'auto_play_audio': autoPlayAudio ? 1 : 0,
    'hardware_tier': hardwareTier?.name,
    'selected_model': selectedModel,
    'ollama_host': ollamaHost,
    'backend_type': backendType.name,
    'gguf_model_path': ggufModelPath,
    'gemma_model_path': gemmaModelPath,
    'gpu_layers': gpuLayers,
    'context_size': contextSize,
    'hugging_face_token': huggingFaceToken,
    'total_conversations': totalConversations,
    'total_minutes': totalMinutes,
    'current_streak': currentStreak,
    'longest_streak': longestStreak,
    'last_active_date': lastActiveDate?.toIso8601String(),
    'vocabulary_count': vocabularyCount,
    'srs_target_retention': srsTargetRetention,
    'srs_daily_new_limit': srsDailyNewLimit,
    'streak_freeze_available': streakFreezeAvailable,
    'streak_freeze_used_today': streakFreezeUsedToday ? 1 : 0,
    'theme_mode': themeMode,
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    name: map['name'] as String?,
    nameFa: map['name_fa'] as String?,
    cefrLevel: CEFRLevel.fromCode(map['cefr_level'] as String? ?? 'A2'),
    nativeLanguage: map['native_language'] as String? ?? 'fa',
    learningGoal: LearningGoal.values.byName(
      map['learning_goal'] as String? ?? 'general',
    ),
    dailyGoalMinutes: map['daily_goal_minutes'] as int? ?? 15,
    preferFinglish: (map['prefer_finglish'] as int? ?? 0) == 1,
    showTranslations: (map['show_translations'] as int? ?? 1) == 1,
    autoPlayAudio: (map['auto_play_audio'] as int? ?? 1) == 1,
    hardwareTier: map['hardware_tier'] != null
        ? HardwareTier.values.byName(map['hardware_tier'] as String)
        : null,
    selectedModel: map['selected_model'] as String?,
    ollamaHost: map['ollama_host'] as String? ?? 'http://localhost:11434',
    backendType: BackendType.values.byName(
      map['backend_type'] as String? ?? 'ollama',
    ),
    ggufModelPath: map['gguf_model_path'] as String?,
    gemmaModelPath: map['gemma_model_path'] as String?,
    gpuLayers: map['gpu_layers'] as int? ?? 999,
    contextSize: map['context_size'] as int? ?? 8192,
    huggingFaceToken: map['hugging_face_token'] as String?,
    totalConversations: map['total_conversations'] as int? ?? 0,
    totalMinutes: map['total_minutes'] as int? ?? 0,
    currentStreak: map['current_streak'] as int? ?? 0,
    longestStreak: map['longest_streak'] as int? ?? 0,
    lastActiveDate: map['last_active_date'] != null
        ? DateTime.parse(map['last_active_date'] as String)
        : null,
    vocabularyCount: map['vocabulary_count'] as int? ?? 0,
    srsTargetRetention:
        (map['srs_target_retention'] as num?)?.toDouble() ?? 0.85,
    srsDailyNewLimit: map['srs_daily_new_limit'] as int? ?? 5,
    streakFreezeAvailable: map['streak_freeze_available'] as int? ?? 1,
    streakFreezeUsedToday:
        (map['streak_freeze_used_today'] as int? ?? 0) == 1,
    themeMode: map['theme_mode'] as String? ?? 'system',
  );
}

enum LearningGoal {
  general('General English', 'انگلیسی عمومی'),
  ielts('IELTS Preparation', 'آمادگی آیلتس'),
  toefl('TOEFL Preparation', 'آمادگی تافل'),
  business('Business English', 'انگلیسی تجاری'),
  academic('Academic English', 'انگلیسی دانشگاهی'),
  immigration('Immigration', 'مهاجرت');

  const LearningGoal(this.nameEn, this.nameFa);
  final String nameEn;
  final String nameFa;
}

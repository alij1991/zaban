import 'package:flutter/foundation.dart';
import '../models/lesson.dart';
import '../models/cefr_level.dart';
import '../services/database_service.dart';

class LessonProvider extends ChangeNotifier {
  LessonProvider({required this.db});

  final DatabaseService db;

  Map<String, LessonProgress> _progress = {};
  Map<String, LessonProgress> get progress => _progress;

  LessonDomain? _selectedDomain;
  LessonDomain? get selectedDomain => _selectedDomain;

  CEFRLevel? _selectedLevel;
  CEFRLevel? get selectedLevel => _selectedLevel;

  List<Scenario> get filteredScenarios {
    var scenarios = LessonData.scenarios;
    if (_selectedDomain != null) {
      scenarios = scenarios.where((s) => s.domain == _selectedDomain).toList();
    }
    if (_selectedLevel != null) {
      scenarios = scenarios.where((s) => s.cefrLevel == _selectedLevel).toList();
    }
    return scenarios;
  }

  Future<void> loadProgress() async {
    _progress = await db.getAllLessonProgress();
    notifyListeners();
  }

  void setDomainFilter(LessonDomain? domain) {
    _selectedDomain = domain;
    notifyListeners();
  }

  void setLevelFilter(CEFRLevel? level) {
    _selectedLevel = level;
    notifyListeners();
  }

  Future<void> markCompleted(String scenarioId, {double? score}) async {
    var prog = _progress[scenarioId] ?? LessonProgress(scenarioId: scenarioId);
    prog.completedCount++;
    prog.lastAttempt = DateTime.now();
    if (score != null && (prog.bestScore == null || score > prog.bestScore!)) {
      prog.bestScore = score;
    }
    _progress[scenarioId] = prog;
    await db.saveLessonProgress(prog);
    notifyListeners();
  }

  LessonProgress? getProgress(String scenarioId) => _progress[scenarioId];
}

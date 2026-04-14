import '../models/cefr_level.dart';

/// CEFR level assessment and tracking service.
///
/// Uses Token Miss Rate (TMR) as a post-generation quality gate.
/// Maintains word-level CEFR lookup tables based on the English Vocabulary
/// Profile (Cambridge/Council of Europe).
///
/// Key improvement over naive approach: unknown words (not in our lists)
/// are treated as B1+ by default, since high-frequency words are well
/// covered in A1/A2 lists and rare words are inherently higher level.
class CEFRService {
  /// Assess approximate CEFR level of user text.
  CEFRAssessment assessText(String text) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    if (words.isEmpty) {
      return CEFRAssessment(level: CEFRLevel.a1, confidence: 0);
    }

    int a1Count = 0, a2Count = 0, b1Count = 0, b2Count = 0, c1Count = 0;
    int unknownCount = 0;

    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^\w]'), '');
      if (clean.isEmpty || clean.length == 1) continue;

      final level = getWordLevel(clean);
      switch (level) {
        case CEFRLevel.a1:
          a1Count++;
        case CEFRLevel.a2:
          a2Count++;
        case CEFRLevel.b1:
          b1Count++;
        case CEFRLevel.b2:
          b2Count++;
        case CEFRLevel.c1 || CEFRLevel.c2:
          c1Count++;
        case null:
          unknownCount++;
      }
    }

    final contentWords = a1Count + a2Count + b1Count + b2Count + c1Count + unknownCount;
    if (contentWords == 0) {
      return CEFRAssessment(level: CEFRLevel.a1, confidence: 0);
    }

    // Grammar complexity signals
    final grammarScore = _assessGrammar(text);

    // Vocabulary complexity ratio (unknown words treated as B1+ signal)
    final advancedVocabRatio = (b2Count + c1Count) / contentWords;
    final intermediateRatio = (b1Count + unknownCount * 0.3) / contentWords;

    // Composite scoring
    double score = 0;
    score += grammarScore; // 0-5 from grammar
    score += advancedVocabRatio * 8; // up to ~2 from advanced vocab
    score += intermediateRatio * 3; // up to ~1.5 from intermediate vocab

    // Average sentence length bonus
    final sentences = text.split(RegExp(r'[.!?]+'));
    final avgLength = words.length / sentences.length.clamp(1, 100);
    if (avgLength > 12) score += 0.5;
    if (avgLength > 18) score += 0.5;
    if (avgLength > 25) score += 0.5;

    CEFRLevel level;
    if (score >= 4.5) {
      level = CEFRLevel.c1;
    } else if (score >= 3.0) {
      level = CEFRLevel.b2;
    } else if (score >= 1.8) {
      level = CEFRLevel.b1;
    } else if (score >= 0.8) {
      level = CEFRLevel.a2;
    } else {
      level = CEFRLevel.a1;
    }

    // Confidence based on text length (longer = more reliable)
    final confidence = (contentWords / 30).clamp(0.2, 0.9);

    return CEFRAssessment(
      level: level,
      confidence: confidence,
      avgSentenceLength: avgLength,
      vocabularyBreakdown: {
        'A1': a1Count,
        'A2': a2Count,
        'B1': b1Count,
        'B2': b2Count,
        'C1': c1Count,
        'unknown': unknownCount,
      },
      grammarScore: grammarScore,
    );
  }

  /// Assess grammar complexity of text. Returns 0-5 score.
  double _assessGrammar(String text) {
    double score = 0;
    final lower = text.toLowerCase();

    // A2 structures
    if (RegExp(r'\b(because|before|after|during|while)\b').hasMatch(lower)) {
      score += 0.3;
    }
    if (RegExp(r'\b(should|could|would|might|must)\b').hasMatch(lower)) {
      score += 0.3;
    }

    // B1 structures
    if (RegExp(r"\b(have|has|had)\s+(been|done|gone|seen|made|taken|given|worked|lived|studied)\b")
        .hasMatch(lower)) {
      score += 0.8; // Present perfect
    }
    if (RegExp(r'\b(if\s+\w+\s+(would|could|will))\b').hasMatch(lower)) {
      score += 0.8; // Conditionals
    }
    if (RegExp(r'\b(used\s+to|be\s+going\s+to)\b').hasMatch(lower)) {
      score += 0.5;
    }
    if (RegExp(r'\b(who|which|that|where|when)\s+\w+\s+\w+').hasMatch(lower)) {
      score += 0.5; // Relative clauses
    }
    if (RegExp(r'\b(was|were|is|are|been)\s+\w+ed\b').hasMatch(lower)) {
      score += 0.6; // Passive voice
    }

    // B2 structures
    if (RegExp(r'\b(although|however|nevertheless|furthermore|whereas|despite|moreover)\b')
        .hasMatch(lower)) {
      score += 1.0; // Complex connectors
    }
    if (RegExp(r'\b(if\s+I\s+were|had\s+\w+\s+would|would\s+have\s+\w+ed)\b')
        .hasMatch(lower)) {
      score += 1.2; // Unreal/past conditionals
    }
    if (RegExp(r'\b(he|she)\s+said\s+that\b').hasMatch(lower)) {
      score += 0.6; // Reported speech
    }
    if (RegExp(r'\b(seems?\s+to|appears?\s+to|tends?\s+to)\b').hasMatch(lower)) {
      score += 0.8; // Hedging
    }

    // C1 structures
    if (RegExp(r'\b(notwithstanding|insofar|inasmuch|whereby|hitherto)\b')
        .hasMatch(lower)) {
      score += 1.5;
    }
    if (RegExp(r'\b(having\s+\w+ed|not\s+only.+but\s+also)\b').hasMatch(lower)) {
      score += 1.2; // Participle clauses, correlative conjunctions
    }

    return score.clamp(0, 5);
  }

  /// Check if tutor output matches target CEFR level.
  /// Returns Token Miss Rate (TMR) — percentage of words above target level.
  ///
  /// Key improvement: unknown words (not in any list) are conservatively
  /// treated as one level above the target for A1/A2 students, since
  /// high-frequency words are well-covered in A1/A2 lists.
  double tokenMissRate(String text, CEFRLevel targetLevel) {
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    if (words.isEmpty) return 0;

    int aboveLevel = 0;
    int total = 0;

    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^\w]'), '');
      if (clean.isEmpty || clean.length == 1) continue;
      total++;

      final wordLevel = getWordLevel(clean);
      if (wordLevel != null && wordLevel > targetLevel) {
        aboveLevel++;
      } else if (wordLevel == null && targetLevel <= CEFRLevel.a2) {
        // For A1/A2 targets: unknown words are likely above level
        // (common words are well-covered in A1/A2 lists)
        aboveLevel++;
      }
    }

    return total > 0 ? aboveLevel / total : 0;
  }

  /// Get CEFR level for a specific word. Returns null if unknown.
  CEFRLevel? getWordLevel(String word) {
    final lower = word.toLowerCase();
    if (_a1Words.contains(lower)) return CEFRLevel.a1;
    if (_a2Words.contains(lower)) return CEFRLevel.a2;
    if (_b1Words.contains(lower)) return CEFRLevel.b1;
    if (_b2Words.contains(lower)) return CEFRLevel.b2;
    if (_c1Words.contains(lower)) return CEFRLevel.c1;
    return null;
  }

  // === CEFR WORD LISTS ===
  // Based on English Vocabulary Profile (Cambridge/Council of Europe)
  // Expanded to ~200+ per level for meaningful coverage.
  // In production, load the full EVP (3000+ entries) from a data file.

  static const _a1Words = <String>{
    // Pronouns & determiners
    'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them',
    'my', 'your', 'his', 'its', 'our', 'their', 'mine', 'yours',
    'this', 'that', 'these', 'those', 'some', 'any', 'no', 'every', 'all',
    // Articles & prepositions
    'the', 'a', 'an', 'in', 'on', 'at', 'to', 'for', 'with', 'from', 'of', 'by',
    'up', 'down', 'out', 'off', 'over', 'under', 'near', 'between',
    // Be, have, do, modals
    'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'can', 'will', 'would',
    // Conjunctions & adverbs
    'and', 'but', 'or', 'not', 'too', 'also', 'very', 'really', 'just',
    'here', 'there', 'now', 'then', 'today', 'tomorrow', 'yesterday',
    // Question words
    'what', 'where', 'when', 'who', 'why', 'how', 'which',
    // Common verbs
    'go', 'come', 'get', 'make', 'take', 'give', 'know', 'think', 'see',
    'want', 'need', 'like', 'say', 'tell', 'look', 'find', 'put', 'use',
    'eat', 'drink', 'sleep', 'work', 'play', 'read', 'write', 'speak',
    'live', 'love', 'sit', 'stand', 'run', 'walk', 'open', 'close',
    'start', 'stop', 'help', 'call', 'listen', 'watch', 'wait', 'try',
    // Common nouns
    'man', 'woman', 'child', 'children', 'boy', 'girl', 'baby', 'person', 'people',
    'name', 'thing', 'time', 'day', 'night', 'morning', 'afternoon', 'evening',
    'year', 'month', 'week', 'hour', 'minute', 'house', 'home', 'room',
    'door', 'window', 'table', 'chair', 'bed', 'car', 'bus', 'train',
    'school', 'class', 'book', 'pen', 'paper', 'phone', 'computer',
    'water', 'food', 'bread', 'milk', 'tea', 'coffee', 'rice', 'meat', 'fruit',
    'family', 'mother', 'father', 'brother', 'sister', 'son', 'daughter',
    'friend', 'teacher', 'student', 'doctor', 'money', 'shop', 'street',
    'city', 'country', 'world', 'hand', 'head', 'eye', 'face', 'body',
    // Common adjectives
    'good', 'bad', 'big', 'small', 'new', 'old', 'young', 'long', 'short',
    'high', 'low', 'hot', 'cold', 'nice', 'happy', 'sad', 'great', 'right',
    'wrong', 'black', 'white', 'red', 'blue', 'green', 'sure', 'ready', 'free',
    // Numbers & misc
    'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
    'hundred', 'thousand', 'first', 'last', 'next', 'other', 'same', 'own',
    'yes', 'ok', 'hello', 'goodbye', 'please', 'thank', 'thanks', 'sorry',
    'much', 'many', 'more', 'most', 'well', 'only', 'again', 'back',
    'if', 'so', 'than',
  };

  static const _a2Words = <String>{
    // Adverbs of frequency/manner
    'usually', 'sometimes', 'always', 'never', 'often', 'already', 'still',
    'yet', 'quite', 'almost', 'enough', 'perhaps', 'probably', 'together',
    'quickly', 'slowly', 'carefully', 'easily', 'recently', 'suddenly',
    // Conjunctions & prepositions
    'during', 'since', 'until', 'while', 'without', 'against', 'among',
    'through', 'across', 'along', 'towards', 'except',
    // Modals & auxiliaries
    'should', 'could', 'might', 'must', 'shall', 'able', 'used',
    // Verbs
    'begin', 'finish', 'continue', 'change', 'move', 'turn', 'carry', 'hold',
    'bring', 'send', 'receive', 'answer', 'ask', 'learn', 'teach', 'study',
    'understand', 'remember', 'forget', 'believe', 'feel', 'seem', 'become',
    'happen', 'keep', 'leave', 'arrive', 'return', 'travel', 'visit', 'stay',
    'spend', 'buy', 'sell', 'pay', 'cost', 'save', 'win', 'lose', 'follow',
    'join', 'meet', 'wear', 'choose', 'decide', 'hope', 'wish', 'plan',
    'agree', 'accept', 'check', 'cross', 'pass', 'fill', 'break', 'build',
    'cook', 'clean', 'wash', 'catch', 'throw', 'drop', 'pick', 'pull', 'push',
    'laugh', 'smile', 'cry', 'shout', 'sing', 'dance', 'draw', 'paint',
    // Nouns
    'weather', 'season', 'spring', 'summer', 'autumn', 'winter',
    'holiday', 'birthday', 'party', 'dinner', 'lunch', 'breakfast',
    'restaurant', 'hotel', 'airport', 'station', 'hospital', 'bank', 'office',
    'garden', 'park', 'beach', 'mountain', 'river', 'lake', 'sea', 'island',
    'ticket', 'passport', 'luggage', 'map', 'key', 'letter', 'message',
    'problem', 'example', 'idea', 'fact', 'news', 'information',
    'music', 'film', 'game', 'sport', 'team', 'match',
    'price', 'dollar', 'percent', 'half', 'double', 'pair',
    'wall', 'floor', 'kitchen', 'bathroom', 'bedroom', 'stairs',
    'boss', 'customer', 'neighbor', 'guest', 'driver',
    // Adjectives
    'important', 'different', 'same', 'easy', 'difficult', 'hard', 'simple',
    'possible', 'impossible', 'necessary', 'popular', 'famous', 'modern',
    'special', 'favorite', 'interesting', 'boring', 'exciting', 'amazing',
    'beautiful', 'ugly', 'terrible', 'wonderful', 'perfect', 'sick',
    'tired', 'hungry', 'thirsty', 'angry', 'afraid', 'worried', 'surprised',
    'lucky', 'poor', 'rich', 'cheap', 'expensive', 'fresh', 'empty', 'full',
    'quiet', 'loud', 'dark', 'light', 'heavy', 'soft', 'thick', 'thin',
    'foreign', 'local', 'main', 'whole', 'single', 'typical',
  };

  static const _b1Words = <String>{
    // Connectors
    'although', 'however', 'therefore', 'moreover', 'meanwhile', 'otherwise',
    'instead', 'whether', 'unless', 'despite', 'according', 'whereas',
    // Adverbs
    'apparently', 'actually', 'especially', 'generally', 'eventually',
    'immediately', 'obviously', 'unfortunately', 'fortunately', 'normally',
    'basically', 'certainly', 'definitely', 'extremely', 'slightly',
    'gradually', 'effectively', 'increasingly', 'particularly', 'previously',
    // Nouns
    'experience', 'opportunity', 'advantage', 'disadvantage', 'achievement',
    'improvement', 'development', 'environment', 'government', 'education',
    'technology', 'society', 'communication', 'relationship', 'responsibility',
    'situation', 'condition', 'opinion', 'attitude', 'behavior', 'ability',
    'skill', 'knowledge', 'research', 'result', 'effect', 'cause',
    'solution', 'method', 'process', 'system', 'structure', 'feature',
    'benefit', 'risk', 'quality', 'quantity', 'variety', 'range',
    'audience', 'community', 'generation', 'culture', 'tradition',
    'industry', 'economy', 'income', 'tax', 'budget', 'investment',
    'pollution', 'climate', 'resource', 'species', 'energy',
    // Verbs
    'recommend', 'suggest', 'consider', 'compare', 'describe', 'explain',
    'discuss', 'disagree', 'complain', 'apologize', 'encourage', 'warn',
    'influence', 'achieve', 'succeed', 'fail', 'manage', 'organize',
    'prepare', 'produce', 'provide', 'require', 'avoid', 'depend',
    'improve', 'develop', 'increase', 'decrease', 'reduce', 'replace',
    'create', 'design', 'discover', 'exist', 'express', 'contain',
    'include', 'involve', 'apply', 'connect', 'combine', 'separate',
    'support', 'protect', 'prevent', 'destroy', 'damage', 'afford',
    'remind', 'recognize', 'realize', 'notice', 'refuse', 'mention',
    'admire', 'respect', 'appreciate', 'trust', 'doubt', 'suspect',
    // Adjectives
    'confident', 'responsible', 'independent', 'traditional', 'professional',
    'available', 'suitable', 'familiar', 'obvious', 'essential', 'reasonable',
    'positive', 'negative', 'serious', 'creative', 'practical', 'original',
    'financial', 'political', 'social', 'physical', 'mental', 'emotional',
    'global', 'specific', 'average', 'convenient', 'complicated',
    'efficient', 'scientific', 'educational', 'environmental',
  };

  static const _b2Words = <String>{
    'nevertheless', 'furthermore', 'consequently', 'whereby', 'hereby',
    'presumably', 'arguably', 'significantly', 'substantially', 'predominantly',
    'comprehensive', 'considerable', 'fundamental', 'sophisticated',
    'controversial', 'contemporary', 'inevitable', 'preliminary', 'ambiguous',
    'abstract', 'adequate', 'apparent', 'arbitrary', 'chronic', 'coherent',
    'compatible', 'compulsory', 'concurrent', 'confidential', 'consistent',
    'conventional', 'deliberate', 'diverse', 'dominant',
    'dramatic', 'elaborate', 'explicit', 'feasible', 'formidable', 'genuine',
    'harsh', 'identical', 'implicit', 'inherent', 'integral', 'legitimate',
    'marginal', 'mutual', 'neutral', 'obscure', 'persistent', 'plausible',
    'pragmatic', 'profound', 'radical', 'reluctant', 'rigid', 'robust',
    'sceptical', 'subtle', 'superficial', 'tangible', 'trivial', 'viable',
    'acknowledge', 'anticipate', 'collaborate', 'constitute', 'demonstrate',
    'emphasize', 'evaluate', 'facilitate', 'generate', 'illustrate',
    'implement', 'investigate', 'justify', 'maintain', 'negotiate',
    'perceive', 'pursue', 'regulate', 'reinforce', 'speculate',
    'accumulate', 'allocate', 'cease', 'clarify', 'coincide', 'compensate',
    'compile', 'comply', 'conceive', 'confine', 'conform', 'contradict',
    'converge', 'depict', 'derive', 'devise', 'diminish', 'displace',
    'distort', 'divert', 'dominate', 'emerge', 'encompass', 'endure',
    'exploit', 'fluctuate', 'formulate', 'hinder', 'inhibit', 'initiate',
    'manipulate', 'mediate', 'modify', 'negate', 'offset', 'orient',
    'infrastructure', 'phenomenon', 'perspective', 'hypothesis', 'criteria',
    'implication', 'correlation', 'methodology', 'bureaucracy', 'legislation',
    'paradigm', 'ideology', 'hierarchy', 'discourse', 'paradox',
    'autonomy', 'consent', 'integrity', 'surveillance', 'solidarity',
  };

  static const _c1Words = <String>{
    'notwithstanding', 'hitherto', 'insofar', 'inasmuch', 'aforementioned',
    'unprecedented', 'disproportionate', 'quintessential', 'idiosyncratic',
    'juxtaposition', 'extrapolate', 'corroborate', 'exacerbate', 'ameliorate',
    'circumvent', 'disseminate', 'encapsulate', 'substantiate', 'undermine',
    'rhetoric', 'epistemology', 'ontology', 'hegemony', 'dichotomy',
    'symbiosis', 'cognoscenti', 'zeitgeist', 'caveat', 'nuance',
    'assimilate', 'coerce', 'confiscate', 'delineate', 'deprecate',
    'elucidate', 'emancipate', 'epitomize', 'exonerate', 'expropriate',
    'galvanize', 'incapacitate', 'insinuate', 'interpolate', 'juxtapose',
    'mitigate', 'obfuscate', 'perpetuate', 'precipitate', 'predicate',
    'promulgate', 'reconcile', 'repudiate', 'stipulate', 'transgress',
    'anachronism', 'antithesis', 'conundrum', 'diatribe', 'epiphany',
    'fallacy', 'hubris', 'impetus', 'innuendo', 'myopia',
    'panacea', 'precursor', 'quandary', 'ramification', 'stigma',
    'acquiesce', 'belie', 'bequeath', 'catalyse', 'denigrate',
    'engender', 'eschew', 'extricate', 'fathom', 'impede',
    'indelible', 'inexorable', 'insidious', 'intransigent', 'laudable',
    'litigious', 'magnanimous', 'nefarious', 'obsequious', 'perfunctory',
    'recalcitrant', 'salient', 'sycophantic', 'tenuous', 'ubiquitous',
  };
}

class CEFRAssessment {
  const CEFRAssessment({
    required this.level,
    required this.confidence,
    this.avgSentenceLength = 0,
    this.vocabularyBreakdown = const {},
    this.grammarScore = 0,
  });

  final CEFRLevel level;
  final double confidence; // 0.0-0.9 based on text length
  final double avgSentenceLength;
  final Map<String, int> vocabularyBreakdown;
  final double grammarScore;
}

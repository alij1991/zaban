/// Pronunciation assessment results for Persian-specific phonological challenges.
class PronunciationResult {
  const PronunciationResult({
    required this.overallScore,
    required this.phonemeScores,
    required this.wordScores,
    this.flaggedIssues = const [],
  });

  /// 0.0 to 1.0 overall pronunciation score
  final double overallScore;

  /// Per-phoneme GOP (Goodness of Pronunciation) scores
  final List<PhonemeScore> phonemeScores;

  /// Per-word scores
  final List<WordScore> wordScores;

  /// Flagged Persian-specific issues
  final List<PronunciationIssue> flaggedIssues;

  double get percentScore => (overallScore * 100).roundToDouble();
}

class PhonemeScore {
  const PhonemeScore({
    required this.phoneme,
    required this.score,
    required this.startTime,
    required this.endTime,
    this.expectedPhoneme,
  });

  final String phoneme;
  final double score; // 0.0 to 1.0
  final double startTime;
  final double endTime;
  final String? expectedPhoneme;

  bool get isWeak => score < 0.6;
}

class WordScore {
  const WordScore({
    required this.word,
    required this.score,
    required this.startTime,
    required this.endTime,
  });

  final String word;
  final double score;
  final double startTime;
  final double endTime;
}

enum PersianPhoneIssue {
  thSubstitution(
    'θ/ð → t/d/s/z',
    'جایگزینی صدای th',
    'The "th" sounds /θ/ (as in "think") and /ð/ (as in "this") don\'t exist in Persian. '
    'You may be substituting /t/, /d/, /s/, or /z/.',
    'صداهای th در فارسی وجود ندارد. ممکن است به جای آن از t، d، s یا z استفاده کنید.',
  ),
  wvMerge(
    'w → v',
    'ادغام w و v',
    'Persian merges /w/ and /v/. English distinguishes them: "west" vs "vest".',
    'در فارسی w و v یکی هستند. در انگلیسی تفاوت دارند: "west" و "vest".',
  ),
  vowelQuality(
    'Vowel confusion',
    'اشتباه مصوت‌ها',
    'Persian has 6 vowels; English has many more. Watch for "sit"/"seat", "full"/"fool" distinctions.',
    'فارسی ۶ مصوت دارد؛ انگلیسی بیشتر. مراقب تفاوت‌های "sit"/"seat" باشید.',
  ),
  consonantCluster(
    'Epenthetic vowel',
    'اضافه کردن مصوت',
    'Persian doesn\'t allow initial consonant clusters. Avoid adding vowels: "street" not "estereet".',
    'فارسی خوشه همخوان اول کلمه ندارد. مصوت اضافه نکنید: "street" نه "estereet".',
  ),
  wordStress(
    'Word stress',
    'تکیه کلمه',
    'Persian stresses the final syllable; English stress varies and is critical for understanding.',
    'در فارسی تکیه روی هجای آخر است؛ در انگلیسی تکیه متغیر و بسیار مهم است.',
  ),
  rhythm(
    'Rhythm pattern',
    'الگوی آهنگ',
    'English is stress-timed (unstressed syllables are shorter). Persian is syllable-timed.',
    'انگلیسی تکیه‌محور است. فارسی هجامحور است.',
  ),
  intonation(
    'Question intonation',
    'آهنگ سوالی',
    'English yes/no questions rise at the end. Persian speakers may use flat intonation.',
    'سوالات بله/خیر انگلیسی آهنگ صعودی دارند. فارسی‌زبانان ممکن است آهنگ صاف استفاده کنند.',
  );

  const PersianPhoneIssue(
    this.shortLabel,
    this.shortLabelFa,
    this.explanation,
    this.explanationFa,
  );

  final String shortLabel;
  final String shortLabelFa;
  final String explanation;
  final String explanationFa;
}

class PronunciationIssue {
  const PronunciationIssue({
    required this.issue,
    required this.word,
    required this.detail,
  });

  final PersianPhoneIssue issue;
  final String word;
  final String detail;
}

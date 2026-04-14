// Persian-specific phoneme mappings for pronunciation assessment.
//
// Maps the 7 critical phonological challenges for Persian speakers
// learning English, with common substitution patterns.

/// Common Persian substitution patterns for English phonemes.
const Map<String, PersianSubstitution> persianSubstitutions = {
  // 1. /θ/ (voiceless th) — absent in Persian
  'θ': PersianSubstitution(
    ipa: 'θ',
    description: 'voiceless "th" (think, three)',
    commonErrors: ['t', 's'],
    exampleWord: 'think',
    persianExplanation: 'این صدا در فارسی وجود ندارد. زبان را بین دندان‌ها بگذارید.',
    tip: 'Place tongue between teeth and blow air. Like biting your tongue gently.',
    tipFa: 'زبان را بین دندان‌ها بگذارید و هوا را از روی آن عبور دهید.',
  ),

  // 2. /ð/ (voiced th) — absent in Persian
  'ð': PersianSubstitution(
    ipa: 'ð',
    description: 'voiced "th" (this, that)',
    commonErrors: ['d', 'z'],
    exampleWord: 'this',
    persianExplanation: 'مثل θ اما با لرزش تارهای صوتی.',
    tip: 'Same tongue position as "th" in think, but add voice (vibrate throat).',
    tipFa: 'مثل "th" در think اما گلو را بلرزانید.',
  ),

  // 3. /w/ vs /v/ — merged in Persian
  'w': PersianSubstitution(
    ipa: 'w',
    description: '"w" sound (well, water)',
    commonErrors: ['v'],
    exampleWord: 'well',
    persianExplanation: 'در فارسی w و v یکی هستند. w لب‌ها را غنچه کنید.',
    tip: 'Round your lips tightly (like kissing), then open. "v" uses teeth on lip.',
    tipFa: 'لب‌ها را غنچه کنید مثل بوسه، سپس باز کنید.',
  ),

  // 4. /ɪ/ vs /iː/ — merged in Persian
  'ɪ': PersianSubstitution(
    ipa: 'ɪ',
    description: 'short "i" (sit, bit)',
    commonErrors: ['iː'],
    exampleWord: 'sit',
    persianExplanation: 'تفاوت بین sit و seat مهم است. sit کوتاه‌تر و شل‌تر است.',
    tip: '"sit" is SHORT and relaxed. "seat" is LONG and tense. Different words!',
    tipFa: '"sit" کوتاه و شل. "seat" بلند و سفت. معنی متفاوت دارند!',
  ),

  // 5. /æ/ — absent in Persian
  'æ': PersianSubstitution(
    ipa: 'æ',
    description: 'flat "a" (cat, bad)',
    commonErrors: ['e', 'ɑː'],
    exampleWord: 'cat',
    persianExplanation: 'این صدا بین "ا" و "اِ" فارسی است.',
    tip: 'Open mouth wide and spread lips. Between "ah" and "eh". Think of saying "yeah" stretched.',
    tipFa: 'دهان را باز کنید و لب‌ها را بکشید. بین "ا" و "اِ".',
  ),

  // 6. /ʊ/ vs /uː/ — merged in Persian
  'ʊ': PersianSubstitution(
    ipa: 'ʊ',
    description: 'short "oo" (book, put)',
    commonErrors: ['uː'],
    exampleWord: 'book',
    persianExplanation: 'تفاوت full و fool مهم است. full کوتاه است.',
    tip: '"full" is short, lips barely rounded. "fool" is long with tight lip rounding.',
    tipFa: '"full" کوتاه، لب‌ها کمی غنچه. "fool" بلند، لب‌ها کاملاً غنچه.',
  ),
};

/// Words that commonly trigger each Persian-specific issue.
const Map<String, List<String>> practiceWords = {
  'th_voiceless': [
    'think', 'three', 'through', 'throw', 'thank',
    'thick', 'thin', 'thought', 'thousand', 'therapy',
  ],
  'th_voiced': [
    'this', 'that', 'the', 'them', 'there',
    'these', 'those', 'they', 'then', 'though',
  ],
  'w_vs_v': [
    'well/veil', 'west/vest', 'wine/vine', 'wet/vet', 'wail/veil',
    'worse/verse', 'wary/vary', 'wiper/viper', 'wow/vow', 'whale/vale',
  ],
  'vowel_pairs': [
    'sit/seat', 'bit/beat', 'fill/feel', 'ship/sheep', 'live/leave',
    'full/fool', 'pull/pool', 'look/Luke', 'could/cooed', 'put/putt',
    'cat/cut', 'bad/bed', 'man/men', 'hat/hot', 'bat/but',
  ],
  'consonant_clusters': [
    'street', 'straight', 'strong', 'spring', 'spread',
    'splash', 'split', 'screen', 'scream', 'script',
    'three', 'through', 'throw', 'shrink', 'shrimp',
  ],
  'word_stress': [
    'present (n) / present (v)', 'record (n) / record (v)',
    'object (n) / object (v)', 'desert (n) / desert (v)',
    'photograph / photographer / photographic',
    'economy / economic / economical',
  ],
};

/// Minimal pairs for targeted practice.
const Map<String, List<List<String>>> minimalPairs = {
  'θ_t': [['thigh', 'tie'], ['three', 'tree'], ['thick', 'tick'], ['thought', 'taught']],
  'ð_d': [['they', 'day'], ['then', 'den'], ['there', 'dare'], ['though', 'dough']],
  'w_v': [['west', 'vest'], ['wine', 'vine'], ['wet', 'vet'], ['wail', 'veil']],
  'ɪ_iː': [['sit', 'seat'], ['bit', 'beat'], ['ship', 'sheep'], ['fill', 'feel']],
  'ʊ_uː': [['full', 'fool'], ['pull', 'pool'], ['look', 'Luke']],
};

class PersianSubstitution {
  const PersianSubstitution({
    required this.ipa,
    required this.description,
    required this.commonErrors,
    required this.exampleWord,
    required this.persianExplanation,
    required this.tip,
    required this.tipFa,
  });

  final String ipa;
  final String description;
  final List<String> commonErrors;
  final String exampleWord;
  final String persianExplanation;
  final String tip;
  final String tipFa;
}

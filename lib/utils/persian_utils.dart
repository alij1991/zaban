// Utilities for Persian language support, Finglish conversion, and text handling.

/// Convert basic Finglish (Latin-script Persian) to Persian script.
/// Handles common romanization patterns used by Iranian digital users.
String finglishToPersian(String input) {
  var result = input.toLowerCase();

  // Multi-character replacements (order matters — longest first)
  const multiMap = {
    'kh': 'خ',
    'gh': 'ق',
    'ch': 'چ',
    'sh': 'ش',
    'zh': 'ژ',
    'th': 'ث',
    'aa': 'آ',
    'oo': 'و',
    'ee': 'ی',
    'ou': 'و',
  };

  for (final entry in multiMap.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }

  // Single character replacements
  const singleMap = {
    'a': 'ا',
    'b': 'ب',
    'c': 'ک',
    'd': 'د',
    'e': 'ه',
    'f': 'ف',
    'g': 'گ',
    'h': 'ه',
    'i': 'ی',
    'j': 'ج',
    'k': 'ک',
    'l': 'ل',
    'm': 'م',
    'n': 'ن',
    'o': 'و',
    'p': 'پ',
    'q': 'ق',
    'r': 'ر',
    's': 'س',
    't': 'ت',
    'u': 'و',
    'v': 'و',
    'w': 'و',
    'x': 'کس',
    'y': 'ی',
    'z': 'ز',
  };

  final buffer = StringBuffer();
  for (final char in result.runes) {
    final c = String.fromCharCode(char);
    buffer.write(singleMap[c] ?? c);
  }

  return buffer.toString();
}

/// Check if text contains Persian/Arabic characters.
bool containsPersian(String text) {
  return RegExp(r'[\u0600-\u06FF\uFB50-\uFDFF\uFE70-\uFEFF]').hasMatch(text);
}

/// Check if text is likely Finglish (Latin-script Persian).
bool isLikelyFinglish(String text) {
  if (containsPersian(text)) return false;
  // Common Finglish patterns
  final finglishPatterns = RegExp(
    r'\b(salam|khoob|mersi|befarmaid|lotfan|chetori|mamnoon|khoda|bale|na|'
    r'man|to|oo|ma|shoma|inha|anja|inja|koja|key|chi|chera|hala|baad|'
    r'ghabl|emrooz|farda|dirooz)\b',
    caseSensitive: false,
  );
  return finglishPatterns.hasMatch(text);
}

/// Normalize Persian text: fix common encoding issues.
String normalizePersian(String text) {
  return text
      // Arabic ي → Persian ی
      .replaceAll('\u064A', '\u06CC')
      // Arabic ك → Persian ک
      .replaceAll('\u0643', '\u06A9')
      // Normalize ZWNJ
      .replaceAll('\u200C\u200C', '\u200C');
}

/// Add Zero-Width Non-Joiner where needed (simplified).
/// ZWNJ is critical for proper Persian text rendering.
String addZWNJ(String text) {
  // Common suffixes that need ZWNJ.
  // replaceAllMapped requires a Function(Match) callback — a bare replacement
  // string with $1/$2 backreferences is NOT supported by Dart and would be
  // emitted verbatim. Each callback extracts the two capture groups explicitly.
  final patterns = [
    RegExp(r'(\S)(ها)\b'), // plural -ha
    RegExp(r'(\S)(های)\b'), // plural -haye
    RegExp(r'(\S)(می)\b'), // verb prefix mi-
    RegExp(r'(\S)(نمی)\b'), // negative prefix nemi-
  ];

  var result = text;
  for (final pattern in patterns) {
    result = result.replaceAllMapped(
      pattern,
      (m) => '${m[1]}\u200C${m[2]}',
    );
  }
  return result;
}

/// Convert Persian/Arabic numerals to Western numerals.
String persianToWesternNumerals(String text) {
  const persianNumerals = '۰۱۲۳۴۵۶۷۸۹';
  const arabicNumerals = '٠١٢٣٤٥٦٧٨٩';
  const westernNumerals = '0123456789';

  var result = text;
  for (int i = 0; i < 10; i++) {
    result = result
        .replaceAll(persianNumerals[i], westernNumerals[i])
        .replaceAll(arabicNumerals[i], westernNumerals[i]);
  }
  return result;
}

/// Convert Western numerals to Persian numerals.
String westernToPersianNumerals(String text) {
  const persianNumerals = '۰۱۲۳۴۵۶۷۸۹';
  const westernNumerals = '0123456789';

  var result = text;
  for (int i = 0; i < 10; i++) {
    result = result.replaceAll(westernNumerals[i], persianNumerals[i]);
  }
  return result;
}

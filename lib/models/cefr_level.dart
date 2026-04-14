enum CEFRLevel {
  a1('A1', 'Beginner', 'مبتدی'),
  a2('A2', 'Elementary', 'مقدماتی'),
  b1('B1', 'Intermediate', 'متوسط'),
  b2('B2', 'Upper Intermediate', 'فوق متوسط'),
  c1('C1', 'Advanced', 'پیشرفته'),
  c2('C2', 'Proficiency', 'مسلط');

  const CEFRLevel(this.code, this.nameEn, this.nameFa);
  final String code;
  final String nameEn;
  final String nameFa;

  static CEFRLevel fromCode(String code) {
    return CEFRLevel.values.firstWhere(
      (l) => l.code == code,
      orElse: () => CEFRLevel.a1,
    );
  }

  bool operator >(CEFRLevel other) => index > other.index;
  bool operator <(CEFRLevel other) => index < other.index;
  bool operator >=(CEFRLevel other) => index >= other.index;
  bool operator <=(CEFRLevel other) => index <= other.index;

  CEFRLevel? get next => index < CEFRLevel.values.length - 1
      ? CEFRLevel.values[index + 1]
      : null;
}

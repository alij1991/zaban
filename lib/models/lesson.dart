import 'cefr_level.dart';

enum LessonDomain {
  dailyLife('Daily Life', 'زندگی روزمره', '🏠'),
  travel('Travel', 'سفر', '✈️'),
  workCareer('Work & Career', 'کار و حرفه', '💼'),
  healthcare('Healthcare', 'بهداشت و درمان', '🏥'),
  social('Social', 'اجتماعی', '👥'),
  education('Education', 'آموزش', '📚');

  const LessonDomain(this.nameEn, this.nameFa, this.icon);
  final String nameEn;
  final String nameFa;
  final String icon;
}

class Scenario {
  const Scenario({
    required this.id,
    required this.domain,
    required this.titleEn,
    required this.titleFa,
    required this.descriptionEn,
    required this.descriptionFa,
    required this.cefrLevel,
    required this.systemPrompt,
    this.targetVocabulary = const [],
    this.targetGrammar = const [],
  });

  final String id;
  final LessonDomain domain;
  final String titleEn;
  final String titleFa;
  final String descriptionEn;
  final String descriptionFa;
  final CEFRLevel cefrLevel;
  final String systemPrompt;
  final List<String> targetVocabulary;
  final List<String> targetGrammar;
}

class LessonProgress {
  LessonProgress({
    required this.scenarioId,
    this.completedCount = 0,
    this.bestScore,
    DateTime? lastAttempt,
  }) : lastAttempt = lastAttempt;

  final String scenarioId;
  int completedCount;
  double? bestScore;
  DateTime? lastAttempt;

  Map<String, dynamic> toMap() => {
    'scenario_id': scenarioId,
    'completed_count': completedCount,
    'best_score': bestScore,
    'last_attempt': lastAttempt?.toIso8601String(),
  };

  factory LessonProgress.fromMap(Map<String, dynamic> map) => LessonProgress(
    scenarioId: map['scenario_id'] as String,
    completedCount: map['completed_count'] as int? ?? 0,
    bestScore: (map['best_score'] as num?)?.toDouble(),
    lastAttempt: map['last_attempt'] != null
        ? DateTime.parse(map['last_attempt'] as String)
        : null,
  );
}

/// Predefined lesson scenarios following Task-Based Language Teaching.
class LessonData {
  static const List<Scenario> scenarios = [
    // Daily Life — A1
    Scenario(
      id: 'daily_greetings_a1',
      domain: LessonDomain.dailyLife,
      titleEn: 'Greetings & Introductions',
      titleFa: 'احوالپرسی و معرفی',
      descriptionEn: 'Practice basic greetings, introductions, and small talk.',
      descriptionFa: 'تمرین احوالپرسی‌های ساده، معرفی و گفتگوی کوتاه.',
      cefrLevel: CEFRLevel.a1,
      systemPrompt: '''You are a friendly neighbor meeting the student for the first time.
Use simple A1-level English: present tense, basic vocabulary (hello, my name is, nice to meet you, where are you from, etc.).
Keep sentences short (5-8 words max). Ask one question at a time.
If the student makes errors, gently recast the correct form naturally.
Scenario: You're both waiting at a bus stop.''',
      targetVocabulary: ['hello', 'name', 'nice', 'meet', 'from', 'live', 'work'],
      targetGrammar: ['present simple be', 'possessive adjectives'],
    ),
    // Daily Life — A2
    Scenario(
      id: 'daily_shopping_a2',
      domain: LessonDomain.dailyLife,
      titleEn: 'Shopping for Groceries',
      titleFa: 'خرید مواد غذایی',
      descriptionEn: 'Practice shopping conversations: asking prices, quantities, and preferences.',
      descriptionFa: 'تمرین مکالمات خرید: پرسیدن قیمت، مقدار و ترجیحات.',
      cefrLevel: CEFRLevel.a2,
      systemPrompt: '''You are a helpful shopkeeper at a grocery store.
Use A2-level English: present simple/continuous, basic past tense, common shopping vocabulary.
Help the student practice: asking for items, quantities, prices, and making preferences.
Introduce 2-3 new vocabulary items naturally during the conversation.
If the student struggles, offer choices rather than open-ended questions.''',
      targetVocabulary: ['how much', 'kilo', 'bag', 'fresh', 'expensive', 'cheap', 'change'],
      targetGrammar: ['how much/many', 'would like', 'countable/uncountable nouns'],
    ),
    // Daily Life — B1
    Scenario(
      id: 'daily_cooking_b1',
      domain: LessonDomain.dailyLife,
      titleEn: 'Sharing Recipes',
      titleFa: 'به اشتراک گذاشتن دستور پخت',
      descriptionEn: 'Describe how to cook your favorite dish and learn a new recipe.',
      descriptionFa: 'توضیح دادن نحوه پخت غذای مورد علاقه و یادگیری دستور پخت جدید.',
      cefrLevel: CEFRLevel.b1,
      systemPrompt: '''You are a cooking enthusiast sharing recipes with a friend.
Use B1-level English: past tenses, conditionals, sequence markers (first, then, after that).
Ask the student to describe a Persian dish they like, then share a simple Western recipe.
Use cooking vocabulary: chop, stir, boil, bake, season, ingredients, etc.
Encourage the student to use sequence words and descriptive language.''',
      targetVocabulary: ['ingredients', 'chop', 'stir', 'boil', 'bake', 'season', 'recipe'],
      targetGrammar: ['imperatives', 'sequence markers', 'passive voice basics'],
    ),
    // Travel — A1
    Scenario(
      id: 'travel_directions_a1',
      domain: LessonDomain.travel,
      titleEn: 'Asking for Directions',
      titleFa: 'پرسیدن مسیر',
      descriptionEn: 'Practice asking and understanding simple directions.',
      descriptionFa: 'تمرین پرسیدن و فهمیدن مسیرهای ساده.',
      cefrLevel: CEFRLevel.a1,
      systemPrompt: '''You are a local person helping a tourist find places.
Use A1-level English: simple directions (go straight, turn left/right, it's next to/near).
The tourist is looking for common places: hotel, restaurant, bus station, hospital.
Use gestures descriptions and landmarks. Keep it very simple.
Ask where they want to go and give step-by-step directions.''',
      targetVocabulary: ['straight', 'left', 'right', 'next to', 'near', 'far', 'corner'],
      targetGrammar: ['imperatives', 'prepositions of place'],
    ),
    // Travel — B1
    Scenario(
      id: 'travel_hotel_b1',
      domain: LessonDomain.travel,
      titleEn: 'Hotel Check-in & Complaints',
      titleFa: 'ورود به هتل و شکایات',
      descriptionEn: 'Check into a hotel, ask about amenities, and handle a room issue.',
      descriptionFa: 'ثبت نام در هتل، پرسیدن درباره امکانات و رسیدگی به مشکل اتاق.',
      cefrLevel: CEFRLevel.b1,
      systemPrompt: '''You are a hotel receptionist. The guest is checking in and will later have a complaint about their room.
Use B1-level English. Phase 1: Handle check-in (reservation, ID, room type, breakfast times).
Phase 2: After check-in, the student will call with a room problem (AC not working, noisy neighbors, etc.).
Practice polite complaint language and problem resolution.
Use hotel vocabulary: reservation, single/double room, amenities, housekeeping.''',
      targetVocabulary: ['reservation', 'check-in', 'amenities', 'complaint', 'housekeeping', 'available'],
      targetGrammar: ['polite requests (could/would)', 'present perfect', 'reported speech basics'],
    ),
    // Work — B1
    Scenario(
      id: 'work_interview_b1',
      domain: LessonDomain.workCareer,
      titleEn: 'Job Interview Practice',
      titleFa: 'تمرین مصاحبه شغلی',
      descriptionEn: 'Practice common job interview questions and professional responses.',
      descriptionFa: 'تمرین سوالات رایج مصاحبه شغلی و پاسخ‌های حرفه‌ای.',
      cefrLevel: CEFRLevel.b1,
      systemPrompt: '''You are a hiring manager interviewing the student for an office position.
Use B1-level English. Ask common interview questions one at a time:
- Tell me about yourself / your experience
- Why do you want this job?
- What are your strengths/weaknesses?
- Where do you see yourself in 5 years?
Give brief feedback after each answer. Coach them on being specific and using examples.
Help with professional vocabulary and formal register.''',
      targetVocabulary: ['experience', 'qualifications', 'strengths', 'responsibilities', 'teamwork'],
      targetGrammar: ['present perfect for experience', 'future plans', 'conditional sentences'],
    ),
    // Work — B2
    Scenario(
      id: 'work_meeting_b2',
      domain: LessonDomain.workCareer,
      titleEn: 'Leading a Team Meeting',
      titleFa: 'اداره جلسه تیمی',
      descriptionEn: 'Practice chairing a meeting: setting agenda, discussing issues, and summarizing.',
      descriptionFa: 'تمرین اداره جلسه: تنظیم دستور کار، بحث درباره مسائل و خلاصه‌سازی.',
      cefrLevel: CEFRLevel.b2,
      systemPrompt: '''You are a team member in a project meeting. The student is the meeting chair.
Use B2-level English. The student should practice:
- Opening the meeting and stating the agenda
- Asking for updates from team members (you play multiple roles)
- Managing disagreements between team members
- Summarizing decisions and assigning action items
Introduce business vocabulary and formal meeting phrases naturally.
Challenge them with a disagreement they need to mediate.''',
      targetVocabulary: ['agenda', 'minutes', 'deadline', 'delegate', 'consensus', 'action items'],
      targetGrammar: ['reported speech', 'passive voice', 'formal register', 'hedging language'],
    ),
    // Healthcare — A2
    Scenario(
      id: 'health_doctor_a2',
      domain: LessonDomain.healthcare,
      titleEn: 'Visiting the Doctor',
      titleFa: 'مراجعه به پزشک',
      descriptionEn: 'Describe symptoms and understand basic medical advice.',
      descriptionFa: 'توضیح علائم بیماری و فهمیدن توصیه‌های پزشکی ساده.',
      cefrLevel: CEFRLevel.a2,
      systemPrompt: '''You are a doctor seeing a patient (the student) who has a cold/flu.
Use A2-level English. Ask about symptoms one at a time.
Help them practice body parts, symptom descriptions (headache, sore throat, fever, cough).
Give simple medical advice: rest, drink water, take medicine.
Speak clearly and check understanding. Offer the Persian word if they seem stuck.''',
      targetVocabulary: ['headache', 'fever', 'cough', 'sore throat', 'prescription', 'rest'],
      targetGrammar: ['present simple for symptoms', 'should for advice', 'how long questions'],
    ),
    // Social — B1
    Scenario(
      id: 'social_party_b1',
      domain: LessonDomain.social,
      titleEn: 'Making Plans with Friends',
      titleFa: 'برنامه‌ریزی با دوستان',
      descriptionEn: 'Suggest activities, negotiate plans, and make arrangements.',
      descriptionFa: 'پیشنهاد فعالیت، مذاکره درباره برنامه‌ها و هماهنگی.',
      cefrLevel: CEFRLevel.b1,
      systemPrompt: '''You are a friend making weekend plans with the student.
Use B1-level English. Practice:
- Suggesting activities (How about...? Why don't we...? Let's...)
- Expressing preferences and declining politely
- Making arrangements (time, place, what to bring)
- Talking about past events you did together
Be a natural conversational partner. Disagree sometimes to practice negotiation.''',
      targetVocabulary: ['suggest', 'prefer', 'arrangement', 'available', 'definitely', 'actually'],
      targetGrammar: ['suggestions (how about/why don\'t we)', 'going to vs will', 'time expressions'],
    ),
    // Education — B2
    Scenario(
      id: 'education_presentation_b2',
      domain: LessonDomain.education,
      titleEn: 'Academic Presentation',
      titleFa: 'ارائه دانشگاهی',
      descriptionEn: 'Practice giving a short academic presentation and answering questions.',
      descriptionFa: 'تمرین ارائه کوتاه دانشگاهی و پاسخ به سوالات.',
      cefrLevel: CEFRLevel.b2,
      systemPrompt: '''You are a university professor and classmate audience. The student will give a short presentation.
Use B2-level English. Help them practice:
- Structuring a presentation (introduction, main points, conclusion)
- Using academic language and transitions
- Handling Q&A after the presentation
First ask them to choose a topic, then guide them through the structure.
After their presentation, ask 2-3 questions and give constructive feedback.
Focus on academic register and formal vocabulary.''',
      targetVocabulary: ['furthermore', 'in conclusion', 'research', 'significant', 'demonstrate', 'hypothesis'],
      targetGrammar: ['passive voice', 'complex sentences', 'academic hedging (seems/appears/tends to)'],
    ),
    // IELTS Speaking — B1+
    Scenario(
      id: 'ielts_part1_b1',
      domain: LessonDomain.education,
      titleEn: 'IELTS Speaking Part 1',
      titleFa: 'آیلتس اسپیکینگ پارت ۱',
      descriptionEn: 'Practice IELTS Speaking Part 1: personal questions about familiar topics.',
      descriptionFa: 'تمرین پارت ۱ اسپیکینگ آیلتس: سوالات شخصی درباره موضوعات آشنا.',
      cefrLevel: CEFRLevel.b1,
      systemPrompt: '''You are an IELTS examiner conducting Part 1 of the Speaking test.
Follow the real IELTS format: ask 4-5 questions on 2-3 familiar topics (home, work/study, hobbies, daily routine, weather, food).
Time: about 4-5 minutes total.
Ask follow-up questions naturally. Keep your questions at the standard IELTS level.
After the practice, give feedback on:
1. Fluency and coherence
2. Vocabulary range
3. Grammar accuracy
4. An estimated band score for this section (be honest but encouraging).
Suggest specific improvements for Persian speakers.''',
      targetVocabulary: ['tend to', 'generally', 'it depends', 'to be honest', 'I\'d say'],
      targetGrammar: ['extended answers', 'present perfect vs simple past', 'frequency adverbs'],
    ),
    // IELTS Speaking — B2
    Scenario(
      id: 'ielts_part2_b2',
      domain: LessonDomain.education,
      titleEn: 'IELTS Speaking Part 2 — Long Turn',
      titleFa: 'آیلتس اسپیکینگ پارت ۲ — صحبت بلند',
      descriptionEn: 'Practice the IELTS cue card: 1 minute preparation, 2 minutes speaking.',
      descriptionFa: 'تمرین کارت موضوع آیلتس: ۱ دقیقه آماده‌سازی، ۲ دقیقه صحبت.',
      cefrLevel: CEFRLevel.b2,
      systemPrompt: '''You are an IELTS examiner conducting Part 2 of the Speaking test.
Give the student a cue card with a topic and 3-4 bullet points. Example topics:
- Describe a place you have visited that you found interesting
- Describe a skill you would like to learn
- Describe a person who has influenced you
Tell them they have 1 minute to prepare (they can take notes), then 1-2 minutes to speak.
Ask 1-2 follow-up questions after they finish.
Then give detailed feedback on organization, vocabulary, fluency, and grammar.
Suggest an estimated band score.''',
      targetVocabulary: ['vividly', 'memorable', 'influenced', 'particularly', 'worthwhile'],
      targetGrammar: ['narrative tenses', 'relative clauses', 'descriptive language'],
    ),
    // Daily Life — A1 (additional)
    Scenario(
      id: 'daily_family_a1',
      domain: LessonDomain.dailyLife,
      titleEn: 'Talking About Family',
      titleFa: 'صحبت درباره خانواده',
      descriptionEn: 'Describe your family members, their jobs, and what they like.',
      descriptionFa: 'توصیف اعضای خانواده، شغل و علایق آنها.',
      cefrLevel: CEFRLevel.a1,
      systemPrompt: '''You are a new classmate getting to know the student.
Use ONLY A1-level English: present simple, "have/has", basic family words.
Keep sentences to 5-7 words maximum. Ask ONE simple question at a time.
Topics: How many brothers/sisters? What does your mother/father do? Do you have children?
If the student struggles, offer yes/no questions instead of open questions.
Use basic vocabulary only: mother, father, brother, sister, son, daughter, family, old, young.''',
      targetVocabulary: ['mother', 'father', 'brother', 'sister', 'old', 'young', 'job'],
      targetGrammar: ['have/has', 'present simple', 'basic questions'],
    ),
    // Daily Life — A1 (additional)
    Scenario(
      id: 'daily_food_a1',
      domain: LessonDomain.dailyLife,
      titleEn: 'Ordering Food',
      titleFa: 'سفارش غذا',
      descriptionEn: 'Practice ordering food and drinks at a simple cafe.',
      descriptionFa: 'تمرین سفارش غذا و نوشیدنی در کافه.',
      cefrLevel: CEFRLevel.a1,
      systemPrompt: '''You are a waiter/waitress at a simple cafe.
Use ONLY A1-level English. The menu has: tea, coffee, water, juice, sandwich, salad, cake, rice, chicken.
Keep sentences to 5-6 words max. Speak slowly and clearly.
Ask: "What would you like?" / "Tea or coffee?" / "Anything else?"
Practice: I would like... / Can I have... / How much is...?
If the student makes errors, gently repeat the correct form.''',
      targetVocabulary: ['menu', 'order', 'would like', 'how much', 'bill', 'delicious'],
      targetGrammar: ['would like', 'can I have', 'how much'],
    ),
    // Travel — A2
    Scenario(
      id: 'travel_airport_a2',
      domain: LessonDomain.travel,
      titleEn: 'At the Airport',
      titleFa: 'در فرودگاه',
      descriptionEn: 'Practice check-in, going through security, and finding your gate.',
      descriptionFa: 'تمرین ثبت‌نام پرواز، عبور از امنیت و پیدا کردن گیت.',
      cefrLevel: CEFRLevel.a2,
      systemPrompt: '''You are an airport check-in agent, then a security officer.
Use A2-level English. Phase 1: Check-in — ask for passport, ticket, window/aisle preference, luggage.
Phase 2: Security — "Please put your bag on the belt", "Do you have any liquids?", "Please remove your belt".
Help the student practice airport vocabulary and polite requests.
Use clear, direct sentences. Offer choices when possible.''',
      targetVocabulary: ['passport', 'boarding pass', 'gate', 'luggage', 'aisle', 'departure'],
      targetGrammar: ['polite requests', 'imperatives', 'prepositions of place'],
    ),
    // IELTS Speaking — B2 (Part 3)
    Scenario(
      id: 'ielts_part3_b2',
      domain: LessonDomain.education,
      titleEn: 'IELTS Speaking Part 3 — Discussion',
      titleFa: 'آیلتس اسپیکینگ پارت ۳ — بحث',
      descriptionEn: 'Practice abstract discussion and opinion-giving on complex topics.',
      descriptionFa: 'تمرین بحث انتزاعی و بیان نظر درباره موضوعات پیچیده.',
      cefrLevel: CEFRLevel.b2,
      systemPrompt: '''You are an IELTS examiner conducting Part 3 of the Speaking test.
This is the most challenging part — abstract discussion related to the Part 2 topic.
Ask questions that require the student to:
- Give and justify opinions ("Do you think technology has made education better or worse? Why?")
- Compare and contrast ("How is education different today compared to 20 years ago?")
- Speculate about the future ("What changes do you think will happen in education in the next decade?")
- Discuss advantages/disadvantages ("What are the pros and cons of online learning?")
Push them to develop their answers with examples and reasoning.
After 5-6 questions, give detailed feedback on:
1. Ability to develop and support arguments
2. Use of complex grammar (conditionals, passive, relative clauses)
3. Vocabulary range for academic discussion
4. Coherence and discourse markers
5. Estimated band score with specific improvement suggestions for Persian speakers.''',
      targetVocabulary: ['whereas', 'on the other hand', 'arguably', 'to a certain extent', 'it could be argued'],
      targetGrammar: ['third conditional', 'passive voice', 'complex noun phrases', 'hedging'],
    ),
    // TOEFL Speaking
    Scenario(
      id: 'toefl_independent_b2',
      domain: LessonDomain.education,
      titleEn: 'TOEFL Speaking — Independent Task',
      titleFa: 'تافل اسپیکینگ — سوال مستقل',
      descriptionEn: 'Practice the TOEFL independent speaking task: state and support a preference.',
      descriptionFa: 'تمرین سوال مستقل اسپیکینگ تافل: بیان و حمایت از ترجیح.',
      cefrLevel: CEFRLevel.b2,
      systemPrompt: '''You are a TOEFL Speaking test practice coach.
Give the student a TOEFL-style independent speaking prompt. Examples:
- "Do you agree or disagree: It is better to study alone than in a group. Use specific reasons."
- "Some people prefer to live in a big city. Others prefer a small town. Which do you prefer and why?"
- "Do you agree or disagree: Children should be required to help with household tasks."
They have 15 seconds to prepare and 45 seconds to speak.
Time them (tell them when to start and when 45 seconds is roughly up).
After their response, score on the TOEFL rubric (0-4):
- Delivery (clarity, pace, pronunciation)
- Language use (grammar, vocabulary)
- Topic development (reasons, details, coherence)
Give an estimated score and specific tips.
Practice 2-3 prompts in one session.''',
      targetVocabulary: ['in my opinion', 'for instance', 'as a result', 'personally', 'specifically'],
      targetGrammar: ['opinion structures', 'supporting with examples', 'transitions'],
    ),
    // Visa Interview
    Scenario(
      id: 'visa_interview_b1',
      domain: LessonDomain.travel,
      titleEn: 'Visa Interview Practice',
      titleFa: 'تمرین مصاحبه ویزا',
      descriptionEn: 'Practice answering common embassy visa interview questions confidently.',
      descriptionFa: 'تمرین پاسخ به سوالات رایج مصاحبه ویزای سفارت.',
      cefrLevel: CEFRLevel.b1,
      systemPrompt: '''You are a visa officer at an embassy conducting an interview.
Be professional but not intimidating. Ask common visa interview questions one at a time:
- What is the purpose of your trip?
- How long do you plan to stay?
- Where will you be staying?
- Who is sponsoring your trip? / How will you fund your trip?
- What do you do for a living? / Are you currently employed?
- Do you have family in [destination country]?
- Have you traveled abroad before?
- Why should we grant you a visa? / What ties do you have to your home country?

Coach the student on:
- Giving clear, concise, confident answers
- Providing specific details (dates, addresses, amounts)
- Showing strong ties to home country (job, property, family)
- Avoiding unnecessary information or nervousness signals

After the practice, give feedback on confidence, clarity, and content.
This is crucial for many Iranian English learners.''',
      targetVocabulary: ['purpose', 'sponsor', 'employed', 'duration', 'itinerary', 'ties'],
      targetGrammar: ['present simple for facts', 'future plans', 'because/so that'],
    ),
  ];

  static List<Scenario> getByDomain(LessonDomain domain) =>
      scenarios.where((s) => s.domain == domain).toList();

  static List<Scenario> getByLevel(CEFRLevel level) =>
      scenarios.where((s) => s.cefrLevel == level).toList();

  static List<Scenario> getByDomainAndLevel(LessonDomain domain, CEFRLevel level) =>
      scenarios.where((s) => s.domain == domain && s.cefrLevel == level).toList();

  static Scenario? getById(String id) {
    try {
      return scenarios.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}

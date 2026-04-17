import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/srs_provider.dart';

/// Progress screen — motivation + transparency dashboard.
///
/// Evidence basis:
///   • Activity heatmap: #1 most impactful Anki add-on; drives "don't break
///     the chain" habit formation (Anki Review Heatmap, 100k+ installs).
///   • Streak with freeze: 3× daily retention rate; reduces quit-after-miss.
///   • Vocabulary range bar: more meaningful than abstract XP points.
///   • 7-day forecast: reduces anxiety about being "behind" on reviews.
///   • Projected milestone: motivates adult goal-oriented learners.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Map<DateTime, int> _activity = {};
  Map<DateTime, int> _forecast = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final srsService = context.read<SRSProvider>().srsService;
    final activity = await srsService.getActivityHistory();
    final forecast = await srsService.getReviewForecast();
    if (mounted) {
      setState(() {
        _activity = activity;
        _forecast = forecast;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final srs = context.watch<SRSProvider>();
    final profile = settings.profile;
    final stats = srs.stats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ─────────────────────────────────────────────────────────
          Text('Your Progress', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              'پیشرفت شما',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(150),
                  ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Streak + Freeze row ───────────────────────────────────────────
          Row(
            children: [
              _StreakCard(
                streak: profile.currentStreak,
                longest: profile.longestStreak,
                freezeAvailable: profile.streakFreezeAvailable,
                freezeUsedToday: profile.streakFreezeUsedToday,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _StatTile(
                      icon: Icons.chat_bubble_outline,
                      label: 'Conversations',
                      value: '${profile.totalConversations}',
                    ),
                    const SizedBox(height: 8),
                    _StatTile(
                      icon: Icons.style_outlined,
                      label: 'Total cards',
                      value: '${stats?.totalCards ?? 0}',
                    ),
                    const SizedBox(height: 8),
                    _StatTile(
                      icon: Icons.check_circle_outline,
                      label: 'Mature cards',
                      value: '${stats?.mature ?? 0}',
                      valueColor: Colors.green,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Vocabulary range bar ──────────────────────────────────────────
          _SectionTitle('Vocabulary Range', 'گستره واژگان'),
          const SizedBox(height: 12),
          _VocabularyRangeBar(
            totalVocab: stats?.totalCards ?? 0,
            cefrLevel: profile.cefrLevel.code,
          ),

          const SizedBox(height: 24),

          // ── 7-day review forecast ─────────────────────────────────────────
          _SectionTitle('Upcoming Reviews (7 days)', 'مرورهای پیش رو (۷ روز)'),
          const SizedBox(height: 12),
          _loading
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _ForecastChart(forecast: _forecast),

          const SizedBox(height: 24),

          // ── Retention rate ────────────────────────────────────────────────
          if (stats != null && stats.totalCards > 0) ...[
            _SectionTitle('Review Quality', 'کیفیت مرور'),
            const SizedBox(height: 12),
            _RetentionBar(
              matureCards: stats.mature,
              totalCards: stats.totalCards,
              targetRetention: profile.srsTargetRetention,
            ),
            const SizedBox(height: 24),
          ],

          // ── Activity heatmap ─────────────────────────────────────────────
          _SectionTitle('Study Activity (12 months)', 'فعالیت مطالعه (۱۲ ماه)'),
          const SizedBox(height: 12),
          _loading
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _ActivityHeatmap(activity: _activity),

          const SizedBox(height: 24),

          // ── FSRS settings panel ───────────────────────────────────────────
          _SectionTitle('SRS Settings', 'تنظیمات مرور'),
          const SizedBox(height: 12),
          _SrsSettingsCard(
            targetRetention: profile.srsTargetRetention,
            dailyNewLimit: profile.srsDailyNewLimit,
            onRetentionChanged: (v) async {
              profile.srsTargetRetention = v;
              await settings.updateProfile(profile);
            },
            onNewLimitChanged: (v) async {
              profile.srsDailyNewLimit = v;
              await settings.updateProfile(profile);
            },
          ),
        ],
      ),
    );
  }
}

// ── Streak card ────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streak,
    required this.longest,
    required this.freezeAvailable,
    required this.freezeUsedToday,
  });
  final int streak;
  final int longest;
  final int freezeAvailable;
  final bool freezeUsedToday;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department,
                    size: 32, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  '$streak',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Text('Day Streak', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Best: $longest days',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // Streak freeze badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: freezeAvailable > 0
                    ? Colors.blue.withAlpha(30)
                    : Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: freezeAvailable > 0
                      ? Colors.blue.withAlpha(80)
                      : Colors.grey.withAlpha(80),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.ac_unit,
                    size: 14,
                    color: freezeAvailable > 0 ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    freezeUsedToday
                        ? 'Freeze used today'
                        : freezeAvailable > 0
                            ? 'Freeze available'
                            : 'No freeze',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          freezeAvailable > 0 ? Colors.blue : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small stat tile ────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary.withAlpha(180)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section title ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.en, this.fa);
  final String en;
  final String fa;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(en, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            '($fa)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(120),
                ),
          ),
        ),
      ],
    );
  }
}

// ── Vocabulary range bar ───────────────────────────────────────────────────

// Approximate word counts per CEFR level (research-based benchmarks)
const _cefrWordTargets = {
  'A1': 500,
  'A2': 1500,
  'B1': 3000,
  'B2': 5000,
  'C1': 8000,
  'C2': 12000,
};

class _VocabularyRangeBar extends StatelessWidget {
  const _VocabularyRangeBar({
    required this.totalVocab,
    required this.cefrLevel,
  });
  final int totalVocab;
  final String cefrLevel;

  @override
  Widget build(BuildContext context) {
    final target = _cefrWordTargets[cefrLevel] ?? 1000;
    final progress = (totalVocab / target).clamp(0.0, 1.0);
    final wordsRemaining = (target - totalVocab).clamp(0, target);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$totalVocab words known',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '$target target for $cefrLevel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).round()} % of $cefrLevel vocabulary',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (wordsRemaining > 0)
                  Text(
                    '$wordsRemaining more to complete $cefrLevel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  )
                else
                  Text(
                    '$cefrLevel complete! 🎉',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 7-day forecast bar chart (no external package) ────────────────────────

class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.forecast});
  final Map<DateTime, int> forecast;

  @override
  Widget build(BuildContext context) {
    if (forecast.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'No upcoming reviews scheduled.\nStart learning words to see your forecast!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(150),
                  ),
            ),
          ),
        ),
      );
    }

    final maxCount =
        forecast.values.isEmpty ? 1 : forecast.values.reduce((a, b) => a > b ? a : b);
    final today = DateTime.now();

    // Build 7 days from tomorrow
    final days = List.generate(7, (i) {
      final d = today.add(Duration(days: i + 1));
      return DateTime(d.year, d.month, d.day);
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((day) {
                final count = forecast[day] ?? 0;
                final barHeight =
                    maxCount > 0 ? (count / maxCount * 80.0) : 0.0;
                final dayLabel =
                    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                        [day.weekday - 1];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (count > 0)
                          Text(
                            '$count',
                            style: const TextStyle(fontSize: 10),
                          ),
                        const SizedBox(height: 2),
                        Container(
                          height: barHeight.clamp(4.0, 80.0),
                          decoration: BoxDecoration(
                            color: count > 0
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withAlpha(180)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 10),
                        ),
                        Text(
                          '${day.day}/${day.month}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'Upcoming reviews per day — staying ahead keeps your queue manageable.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(120),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Retention quality bar ─────────────────────────────────────────────────

class _RetentionBar extends StatelessWidget {
  const _RetentionBar({
    required this.matureCards,
    required this.totalCards,
    required this.targetRetention,
  });
  final int matureCards;
  final int totalCards;
  final double targetRetention;

  @override
  Widget build(BuildContext context) {
    final maturity = totalCards > 0 ? matureCards / totalCards : 0.0;
    final targetPct = (targetRetention * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mature cards: $matureCards / $totalCards',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Target: $targetPct %',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Stack(
              children: [
                LinearProgressIndicator(
                  value: maturity,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                  color: Colors.green,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                ),
                // Target retention marker
                Positioned(
                  left: MediaQuery.of(context).size.width * targetRetention *
                      0.5, // rough approximation
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A "mature" card has an interval ≥ 21 days — long-term memory.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(120),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Activity heatmap (GitHub-style) ───────────────────────────────────────

class _ActivityHeatmap extends StatelessWidget {
  const _ActivityHeatmap({required this.activity});
  final Map<DateTime, int> activity;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 40,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(80)),
                const SizedBox(height: 8),
                Text(
                  'No activity yet. Start reviewing words!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(150),
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final maxCount = activity.values.isEmpty
        ? 1
        : activity.values.reduce((a, b) => a > b ? a : b);

    // Build 52 weeks of grid cells (364 days)
    final today = DateTime.now();
    final gridStart = today.subtract(const Duration(days: 363));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(52, (week) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Column(
                      children: List.generate(7, (day) {
                        final date = gridStart
                            .add(Duration(days: week * 7 + day));
                        final key = DateTime(date.year, date.month, date.day);
                        final count = activity[key] ?? 0;
                        final intensity =
                            maxCount > 0 ? count / maxCount : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Tooltip(
                            message: count > 0
                                ? '${date.day}/${date.month}: $count reviews'
                                : '${date.day}/${date.month}: no reviews',
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: count == 0
                                    ? Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                    : Color.lerp(
                                        Colors.green.shade200,
                                        Colors.green.shade800,
                                        intensity,
                                      ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Less',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10),
                ),
                const SizedBox(width: 4),
                ...List.generate(
                  5,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                            : Color.lerp(Colors.green.shade200,
                                Colors.green.shade800, i / 4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'More',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── FSRS settings card ─────────────────────────────────────────────────────

class _SrsSettingsCard extends StatelessWidget {
  const _SrsSettingsCard({
    required this.targetRetention,
    required this.dailyNewLimit,
    required this.onRetentionChanged,
    required this.onNewLimitChanged,
  });
  final double targetRetention;
  final int dailyNewLimit;
  final Future<void> Function(double) onRetentionChanged;
  final Future<void> Function(int) onNewLimitChanged;

  @override
  Widget build(BuildContext context) {
    // Projected daily review load (rule of thumb: 7× new cards/day once mature)
    final projectedLoad = dailyNewLimit * 7;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Target retention
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Target retention',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  '${(targetRetention * 100).round()} %',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Slider(
              value: targetRetention,
              min: 0.70,
              max: 0.97,
              divisions: 27,
              onChanged: onRetentionChanged,
            ),
            Text(
              'Higher = more reviews, better recall. 85 % is optimal for most learners.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(120),
                  ),
            ),
            const Divider(height: 24),

            // Daily new cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('New cards per day',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  '$dailyNewLimit cards',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Slider(
              value: dailyNewLimit.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              onChanged: (v) => onNewLimitChanged(v.round()),
            ),
            Text(
              'Projected daily review load at maturity: ~$projectedLoad cards/day. '
              'Start with 5 and increase only after 7 consistent days.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: projectedLoad > 150
                        ? Colors.orange
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(120),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

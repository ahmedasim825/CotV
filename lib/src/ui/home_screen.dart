import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/calendar_sync_models.dart';
import '../models/daily_prayer_times.dart';
import '../models/notification_models.dart';
import '../providers/calendar_providers.dart';
import '../providers/notification_providers.dart';
import '../providers/prayer_providers.dart';
import 'theme/app_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/eyebrow_pill.dart';
import 'widgets/floating_header.dart';
import 'widgets/glow_pill_button.dart';
import 'widgets/ph_light_icons.dart';
import 'widgets/prayer_grid_tile.dart';
import 'widgets/prayer_hero_card.dart';
import 'widgets/reveal_on_entrance.dart';
import 'widgets/status_card.dart';

/// Exercises all three Part 1 services end to end: today's computed prayer
/// times as an asymmetrical bento grid, and calendar sync / notification
/// scheduling with visible loading/success/error states.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerTimesAsync = ref.watch(todayPrayerTimesProvider);
    final calendarSyncAsync = ref.watch(calendarSyncControllerProvider);
    final notificationScheduleAsync = ref.watch(notificationScheduleControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: AppPalette.amber,
            backgroundColor: AppPalette.surface,
            onRefresh: () async => ref.invalidate(todayPrayerTimesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 56),
              children: [
                Center(
                  child: RevealOnEntrance(
                    child: FloatingHeader(
                      onRefresh: () => ref.invalidate(todayPrayerTimesProvider),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                RevealOnEntrance(
                  delay: const Duration(milliseconds: 60),
                  child: const _SectionHeader(
                    eyebrow: "TODAY'S SCHEDULE",
                    title: 'Prayer times',
                  ),
                ),
                const SizedBox(height: 20),
                prayerTimesAsync.when(
                  data: (timings) => _PrayerBento(timings: timings),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(
                      child: CircularProgressIndicator(color: AppPalette.amber, strokeWidth: 2.5),
                    ),
                  ),
                  error: (error, stackTrace) =>
                      StatusCard(message: '$error', tone: StatusTone.error),
                ),
                const SizedBox(height: 48),
                RevealOnEntrance(
                  delay: const Duration(milliseconds: 140),
                  child: const _SectionHeader(
                    eyebrow: 'AUTOMATION',
                    title: 'Prayer Lockout calendar',
                    subtitle:
                        'Creates a dedicated calendar iOS Shortcuts and Jomo can key '
                        'off of to trigger focus mode during each prayer window.',
                  ),
                ),
                const SizedBox(height: 18),
                RevealOnEntrance(
                  delay: const Duration(milliseconds: 180),
                  child: GlowPillButton(
                    label: 'Sync next 7 days',
                    icon: PhLight.calendarCheck,
                    loading: calendarSyncAsync.isLoading,
                    onPressed: calendarSyncAsync.isLoading
                        ? null
                        : () => ref.read(calendarSyncControllerProvider.notifier).syncDays(7),
                  ),
                ),
                _CalendarStatus(calendarSyncAsync: calendarSyncAsync),
                const SizedBox(height: 48),
                RevealOnEntrance(
                  delay: const Duration(milliseconds: 220),
                  child: const _SectionHeader(
                    eyebrow: 'ALERTS',
                    title: 'Adhan notifications',
                    subtitle: 'Exact Adhan alerts plus a pre-Adhan reminder for each prayer.',
                  ),
                ),
                const SizedBox(height: 18),
                RevealOnEntrance(
                  delay: const Duration(milliseconds: 260),
                  child: Row(
                    children: [
                      Expanded(
                        child: GlowPillButton(
                          label: 'Schedule 7 days',
                          icon: PhLight.bellSimpleRinging,
                          expand: true,
                          loading: notificationScheduleAsync.isLoading,
                          onPressed: notificationScheduleAsync.isLoading
                              ? null
                              : () => ref
                                  .read(notificationScheduleControllerProvider.notifier)
                                  .scheduleDays(7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GlowPillButton(
                        label: 'Cancel',
                        icon: PhLight.xCircle,
                        filled: false,
                        loading: false,
                        onPressed: notificationScheduleAsync.isLoading
                            ? null
                            : () => ref
                                .read(notificationScheduleControllerProvider.notifier)
                                .cancelAll(),
                      ),
                    ],
                  ),
                ),
                _NotificationStatus(notificationScheduleAsync: notificationScheduleAsync),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.eyebrow, required this.title, this.subtitle});

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowPill(label: eyebrow),
        const SizedBox(height: 12),
        Text(title, style: AppTypography.display(size: 30, weight: FontWeight.w500)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: AppTypography.ui(size: 13.5, color: AppPalette.textMuted, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// The asymmetrical bento layout: the next upcoming prayer fills a wide
/// hero cell, every other prayer sits in a two-column grid beneath it.
class _PrayerBento extends ConsumerWidget {
  const _PrayerBento({required this.timings});

  final DailyPrayerTimes timings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final entries = timings.asMap().entries.toList();

    MapEntry<PrayerLabel, DateTime>? next;
    for (final entry in entries) {
      if (entry.value.isAfter(now)) {
        next = entry;
        break;
      }
    }

    var isTomorrow = false;
    if (next == null) {
      final tomorrow = startOfDay(now.add(const Duration(days: 1)));
      final tomorrowTimings = ref.watch(dailyPrayerTimesProvider(tomorrow));
      next = MapEntry(PrayerLabel.fajr, tomorrowTimings.fajr);
      isTomorrow = true;
    }

    final rest = entries.where((e) => e.key != next!.key).toList();

    return Column(
      children: [
        RevealOnEntrance(
          delay: const Duration(milliseconds: 100),
          child: PrayerHeroCard(
            prayer: next.key,
            time: next.value,
            now: now,
            isTomorrow: isTomorrow,
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rest.length,
          // A fixed main-axis extent rather than childAspectRatio: the
          // tile's contents are a fixed stack of icon + labels, so deriving
          // its height from its width overflowed on narrow screens (an
          // iPhone 14 Pro was 0.4px short).
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 146,
          ),
          itemBuilder: (context, index) {
            final entry = rest[index];
            return RevealOnEntrance(
              delay: Duration(milliseconds: 140 + index * 50),
              child: PrayerGridTile(
                prayer: entry.key,
                time: entry.value,
                isPast: !isTomorrow && entry.value.isBefore(now),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CalendarStatus extends StatelessWidget {
  const _CalendarStatus({required this.calendarSyncAsync});

  final AsyncValue<CalendarSyncResult?> calendarSyncAsync;

  @override
  Widget build(BuildContext context) {
    return calendarSyncAsync.when(
      data: (result) {
        if (result == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: StatusCard(
            message: 'Synced ${result.eventsCreated} events '
                '(removed ${result.eventsRemoved} stale) to the Prayer '
                'Lockout calendar.',
            tone: StatusTone.success,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: StatusCard(message: '$error', tone: StatusTone.error),
      ),
    );
  }
}

class _NotificationStatus extends StatelessWidget {
  const _NotificationStatus({required this.notificationScheduleAsync});

  final AsyncValue<NotificationScheduleResult?> notificationScheduleAsync;

  @override
  Widget build(BuildContext context) {
    return notificationScheduleAsync.when(
      data: (result) {
        if (result == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: StatusCard(
            message: 'Scheduled ${result.notificationsScheduled} notifications '
                'over ${result.daysScheduled} days.',
            tone: StatusTone.success,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: StatusCard(message: '$error', tone: StatusTone.error),
      ),
    );
  }
}

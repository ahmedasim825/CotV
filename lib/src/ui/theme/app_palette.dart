import 'package:flutter/material.dart';

/// The six prayer hues, one per adhan.
@immutable
class PrayerHues {
  const PrayerHues({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final Color fajr;
  final Color sunrise;
  final Color dhuhr;
  final Color asr;
  final Color maghrib;
  final Color isha;
}

/// Every colour the app paints with.
///
/// One instance exists — [kPalette] in `app_theme.dart`. The app used to
/// carry six of these behind a picker; the class survives the collapse so
/// that the ~246 `context.palette.<token>` call sites keep reading a name
/// rather than a literal, which is what keeps the scheme editable in one
/// place.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.glassFill,
    required this.glassBorder,
    required this.cardFill,
    required this.glassSpecular,
    required this.hairline,
    required this.innerHighlight,
    required this.accent,
    required this.accentBright,
    required this.accentDeep,
    required this.onAccent,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.danger,
    required this.success,
    required this.taskRing,
    required this.reminderRing,
    required this.priorityLow,
    required this.priorityMedium,
    required this.priorityHigh,
    required this.shadow,
    required this.glowPrimary,
    required this.glowSecondary,
    required this.prayerHues,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color glassFill;
  final Color glassBorder;

  /// The dashboard card's fill: white at 2%. Almost nothing, deliberately —
  /// the card reads as its rim and its contents rather than as a plate, and
  /// the ambient glow behind it comes straight through.
  final Color cardFill;
  final Color glassSpecular;
  final Color hairline;
  final Color innerHighlight;
  final Color accent;
  final Color accentBright;
  final Color accentDeep;
  final Color onAccent;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color danger;
  final Color success;

  /// The ring on a task row in the iOS agenda card.
  ///
  /// Only the agenda card reads these two: in a list that interleaves tasks
  /// and reminders under one title, the ring colour is the only thing saying
  /// which kind a row is, so each gets a hue of its own rather than sharing
  /// [accent]. Neither is a general-purpose token — nothing else should
  /// borrow them.
  final Color taskRing;

  /// The ring on a reminder row in the iOS agenda card. Always this colour,
  /// whether or not the reminder is overdue — lateness is carried by the due
  /// line under the title, not by the ring.
  final Color reminderRing;

  /// The three priority hues, used as the dot on a task or reminder row and
  /// as the tint on the priority badge and the timeline blocks.
  ///
  /// All three are their own fields rather than being borrowed from [danger]
  /// and [secondary] the way they used to be: priority is one scale, and a
  /// scale whose top step is literally the app's error red cannot be retuned
  /// without also restyling every failure state. Rows render them at 60%;
  /// the alpha is applied at the call site, not baked in here.
  final Color priorityLow;
  final Color priorityMedium;
  final Color priorityHigh;
  final Color shadow;
  final Color glowPrimary;
  final Color glowSecondary;
  final PrayerHues prayerHues;

  bool get isDark => brightness == Brightness.dark;

  /// The tight second shadow directly beneath a floating surface. Darker and
  /// much smaller than [shadow], which is the wide ambient one.
  Color get shadowContact => const Color(0xFF000000).withValues(alpha: 0.45);

  /// The lit and shaded ends of a glass rim, running top-leading to
  /// bottom-trailing. Derived rather than two more constructor fields: every
  /// pane in the app is lit from the same direction, so these are a property
  /// of the palette's light, not of any one surface.
  Color get rimLit => textPrimary.withValues(alpha: 0.35);

  Color get rimShade => textPrimary.withValues(alpha: 0.05);

  /// The bento card on the tasks screen: a 3% white plate under a 6% white
  /// rim. Far quieter than [cardFill]/[hairline] (2%/10%) because the card is
  /// a grouping device rather than a surface — the rows are the content, and
  /// the plate only has to say where the day starts and stops.
  Color get bentoFill => textPrimary.withValues(alpha: 0.03);

  /// The bento card's rim, and the rules between its rows. One token for both:
  /// the divider is the same line as the border, just drawn inside.
  Color get bentoBorder => textPrimary.withValues(alpha: 0.06);

  /// An unchecked completion box. A shade above [bentoFill] so the control
  /// separates from the card it sits on without needing a heavier rim.
  Color get checkboxFill => textPrimary.withValues(alpha: 0.04);

  /// A reminder's due line once the moment has passed. Hotter than [danger]
  /// on purpose — [danger] marks a failure the app is reporting, this marks a
  /// time the user has missed.
  Color get dueOverdue => const Color(0xFFF20606);

  Color get accentSoft => accent.withValues(alpha: 0.16);

  /// The near-full-screen task sheet's plate: #222226 at half strength over a
  /// blur. Its own colour rather than [surface] at an alpha, because the sheet
  /// is the one surface in the app that covers the ground rather than floating
  /// a card above it, and it is tuned against the blur it sits on.
  Color get sheetGlass => const Color(0x80222226);

  /// A form field's box on that sheet: 6% white under a 3% rim.
  ///
  /// The inverse of the bento ladder — [bentoFill] is 3% under a 6% rim — and
  /// deliberately so. A bento card groups rows *under* one plate, where the rim
  /// does the work of saying where the group ends. A field is a target you type
  /// into, so the plate is what has to read and the rim only has to catch the
  /// edge.
  Color get fieldFill => textPrimary.withValues(alpha: 0.06);

  Color get fieldBorder => textPrimary.withValues(alpha: 0.03);

  /// The rule between two fields sharing one box. Opaque rather than a white
  /// alpha like [bentoBorder]: the sheet is itself translucent, and a rule
  /// defined as a fraction of white would change strength with whatever
  /// happened to be behind the sheet at the time.
  Color get fieldDivider => const Color(0xFF2C2C2E);

  /// A small control riding on top of a field box — the Subject dropdown. One
  /// step lighter than [fieldFill], because it has to read as a thing you press
  /// while sitting on a plate that is already a lifted surface.
  Color get pillFill => const Color(0x993A3A3C);

  Color get meterTrack => textPrimary.withValues(alpha: 0.08);

  Color get heroTint =>
      Color.alphaBlend(accent.withValues(alpha: isDark ? 0.07 : 0.05), surface);

  Color get scrim => isDark ? const Color(0xB3000000) : const Color(0x66000000);
}

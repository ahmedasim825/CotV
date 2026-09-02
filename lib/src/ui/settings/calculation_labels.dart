import 'package:adhan/adhan.dart';

/// Display names for the `adhan` package's calculation methods.
///
/// The package exposes them as snake_case enum values; these are the names
/// the authorities actually publish under, which is what a user picking one
/// will recognise.
String calculationMethodLabel(CalculationMethod method) {
  switch (method) {
    case CalculationMethod.muslim_world_league:
      return 'Muslim World League';
    case CalculationMethod.egyptian:
      return 'Egyptian General Authority';
    case CalculationMethod.karachi:
      return 'University of Karachi';
    case CalculationMethod.umm_al_qura:
      return 'Umm al-Qura, Makkah';
    case CalculationMethod.dubai:
      return 'Dubai';
    case CalculationMethod.moon_sighting_committee:
      return 'Moon Sighting Committee';
    case CalculationMethod.north_america:
      return 'ISNA, North America';
    case CalculationMethod.kuwait:
      return 'Kuwait';
    case CalculationMethod.qatar:
      return 'Qatar';
    case CalculationMethod.singapore:
      return 'Singapore';
    case CalculationMethod.turkey:
      return 'Diyanet, Turkey';
    case CalculationMethod.tehran:
      return 'Tehran';
    case CalculationMethod.other:
      return 'Other (no adjustment)';
  }
}

/// The Fajr/Isha angles each method uses — the detail that actually
/// distinguishes them, shown under the name so the choice is informed.
String calculationMethodNote(CalculationMethod method) {
  switch (method) {
    case CalculationMethod.muslim_world_league:
      return 'Fajr 18° · Isha 17°';
    case CalculationMethod.egyptian:
      return 'Fajr 19.5° · Isha 17.5°';
    case CalculationMethod.karachi:
      return 'Fajr 18° · Isha 18°';
    case CalculationMethod.umm_al_qura:
      return 'Fajr 18.5° · Isha 90 min after Maghrib';
    case CalculationMethod.dubai:
      return 'Fajr 18.2° · Isha 18.2°';
    case CalculationMethod.moon_sighting_committee:
      return 'Fajr 18° · Isha 18°, seasonally adjusted';
    case CalculationMethod.north_america:
      return 'Fajr 15° · Isha 15°';
    case CalculationMethod.kuwait:
      return 'Fajr 18° · Isha 17.5°';
    case CalculationMethod.qatar:
      return 'Fajr 18° · Isha 90 min after Maghrib';
    case CalculationMethod.singapore:
      return 'Fajr 20° · Isha 18°';
    case CalculationMethod.turkey:
      return 'Fajr 18° · Isha 17°';
    case CalculationMethod.tehran:
      return 'Fajr 17.7° · Isha 14°';
    case CalculationMethod.other:
      return 'Zero angles — only for a custom setup';
  }
}

String madhabLabel(Madhab madhab) {
  switch (madhab) {
    case Madhab.shafi:
      return 'Shafi';
    case Madhab.hanafi:
      return 'Hanafi';
  }
}

/// How the madhab changes Asr, which is the only prayer it affects.
String madhabNote(Madhab madhab) {
  switch (madhab) {
    case Madhab.shafi:
      return 'Asr at one shadow length (also Maliki, Hanbali)';
    case Madhab.hanafi:
      return 'Asr at two shadow lengths — later in the afternoon';
  }
}

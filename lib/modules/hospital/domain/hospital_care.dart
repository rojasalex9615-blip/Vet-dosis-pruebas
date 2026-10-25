import '../../doses/domain/quantity.dart';
import 'hospital_models.dart';

enum HospitalCareKind {
  feeding('Alimentación'),
  catheterReview('Revisión de catéter'),
  equipmentChange('Cambio de equipo');

  const HospitalCareKind(this.title);
  final String title;
}

/// An entered professional instruction, never a generated clinical protocol.
class HospitalCareDraft {
  /// Builds care text from explicit feeding or device instructions.
  ///
  /// Feeding requires food, a positive decimal portion, and `g`, `ml`, or
  /// `porción`; other kinds require a device or site. Throws [FormatException]
  /// for missing or oversized text, invalid quantities, or unsupported units.
  HospitalCareDraft({
    required this.kind,
    required String instructions,
    String food = '',
    String portion = '',
    String unit = '',
    String device = '',
  }) {
    final notes = hospitalText(instructions, max: 3000);
    if (kind == HospitalCareKind.feeding) {
      final diet = hospitalText(food, max: 200);
      final quantity = Quantity.parse(portion);
      if (!quantity.positive) {
        throw const FormatException('La porción debe ser mayor que cero.');
      }
      if (!['g', 'ml', 'porción'].contains(unit)) {
        throw const FormatException('Selecciona la unidad de la porción.');
      }
      label = '${kind.title} · $diet';
      details =
          'Alimento: $diet\n'
          'Porción indicada por horario: ${portion.trim()} $unit\n'
          'Indicaciones: $notes';
    } else {
      final identifier = hospitalText(device, max: 200);
      label = '${kind.title} · $identifier';
      details = 'Dispositivo / sitio: $identifier\nIndicaciones: $notes';
    }
    hospitalText(label);
    hospitalText(details, max: 4000);
  }

  final HospitalCareKind kind;
  late final String label, details;
}

/// Expands only the dates and wall-clock times explicitly reviewed by the user.
/// Limits bound the existing scheduling RPC; they are not clinical intervals.
///
/// Uses the date components inclusively in the device's local time zone and
/// returns an unmodifiable list of sorted UTC instants. [minutesOfDay] contains
/// distinct minutes since midnight (0 to 1439). Throws [FormatException] for
/// spans outside 1 to 31 days, empty or repeated times, more than 200 entries,
/// nonexistent local times, or any instant at or before [now].
List<DateTime> dailyCareSchedule({
  required DateTime firstDay,
  required DateTime lastDay,
  required List<int> minutesOfDay,
  required DateTime now,
}) {
  final first = DateTime.utc(firstDay.year, firstDay.month, firstDay.day);
  final last = DateTime.utc(lastDay.year, lastDay.month, lastDay.day);
  final count = last.difference(first).inDays + 1;
  if (count < 1 || count > 31) {
    throw const FormatException(
      'Selecciona entre 1 y 31 días de programación.',
    );
  }
  if (minutesOfDay.isEmpty ||
      minutesOfDay.any((m) => m < 0 || m >= 24 * 60) ||
      minutesOfDay.toSet().length != minutesOfDay.length) {
    throw const FormatException('Añade horarios válidos sin repetirlos.');
  }
  if (count * minutesOfDay.length > 200) {
    throw const FormatException('Programa como máximo 200 horarios por orden.');
  }
  final times = <DateTime>[];
  for (
    var day = first;
    !day.isAfter(last);
    day = day.add(const Duration(days: 1))
  ) {
    for (final minute in minutesOfDay) {
      final local = DateTime(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      );
      // DateTime normalizes nonexistent wall-clock times at DST transitions.
      if (local.year != day.year ||
          local.month != day.month ||
          local.day != day.day ||
          local.hour != minute ~/ 60 ||
          local.minute != minute % 60) {
        throw const FormatException(
          'Un horario no existe en la zona del dispositivo. Revisa las fechas y horas.',
        );
      }
      times.add(local);
    }
  }
  return validateSchedule(times, now: now);
}

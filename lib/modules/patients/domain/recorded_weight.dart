import '../../forms/clinical/clinical_models.dart';

/// Identifies a persisted measurement. Selecting it does not validate a dose.
class RecordedPatientWeight {
  RecordedPatientWeight({
    required this.id,
    required this.clinicId,
    required this.patientId,
    required this.patientName,
    required this.caseId,
    required String kg,
    required this.observedAt,
    required this.performedBy,
    required this.recordedBy,
    required this.recordedAt,
  }) : kg = clinicalNumber(kg, 'weight') {
    if ([
      id,
      clinicId,
      patientId,
      caseId,
      performedBy,
      recordedBy,
    ].any((s) => s.trim().isEmpty)) {
      throw const FormatException('Medición de peso incompleta o inválida.');
    }
  }

  final String id, clinicId, patientId, patientName, caseId, kg;
  final String performedBy, recordedBy;
  final DateTime observedAt, recordedAt;

  bool sameMeasurement(RecordedPatientWeight other) =>
      id == other.id &&
      clinicId == other.clinicId &&
      patientId == other.patientId &&
      caseId == other.caseId &&
      kg == other.kg &&
      observedAt == other.observedAt &&
      performedBy == other.performedBy &&
      recordedBy == other.recordedBy &&
      recordedAt == other.recordedAt;
}

/// PostgreSQL snapshots return timestamp offsets; form input uses strict UTC.
DateTime recordedWeightInstant(String text) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(text);
  if (match == null) throw const FormatException('Hora de medición inválida.');
  clinicalInstant('${match[1]}Z');
  final zone = match[2]!;
  if (zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 ||
          int.parse(zone.substring(4)) > 59)) {
    throw const FormatException('Zona horaria inválida.');
  }
  return DateTime.parse(text).toUtc();
}

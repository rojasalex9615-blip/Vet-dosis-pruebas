import 'hospital_models.dart';

/// Returns an unmodifiable checklist with whitespace trimmed from each step.
///
/// Throws [FormatException] unless there are 1 to 30 distinct, nonempty steps
/// of at most 500 characters each after trimming.
List<String> isolationSteps(Iterable<String> input) {
  final steps = input.map((s) => s.trim()).toList();
  if (steps.isEmpty ||
      steps.length > 30 ||
      steps.toSet().length != steps.length ||
      steps.any((s) => s.isEmpty || s.length > 500)) {
    throw const FormatException(
      'Captura de 1 a 30 pasos distintos, de hasta 500 caracteres cada uno.',
    );
  }
  return List.unmodifiable(steps);
}

class HospitalIsolation {
  HospitalIsolation({
    required this.stayId,
    required this.active,
    required this.reference,
    required this.steps,
    required this.reason,
    required this.changedBy,
    required this.changedAt,
  });
  final String stayId, reference, reason, changedBy;
  final List<String> steps;
  final bool active;
  final DateTime changedAt;
  /// Reads isolation status and its protocol snapshot for [clinic].
  ///
  /// Throws [FormatException] for a clinic mismatch or invalid status, text,
  /// checklist, or timestamp. Incorrect runtime field types cause type errors.
  factory HospitalIsolation.read(Map<String, dynamic> row, String clinic) {
    if (row['clinic_id'] != clinic || row['active'] is! bool) {
      throw const FormatException('Contrato de aislamiento no disponible.');
    }
    return HospitalIsolation(
      stayId: hospitalText(row['stay_id'] as String),
      active: row['active'] as bool,
      reference: hospitalText(row['protocol_reference'] as String, max: 1000),
      steps: isolationSteps((row['steps'] as List).cast<String>()),
      reason: hospitalText(row['reason'] as String, max: 1000),
      changedBy: hospitalText(row['changed_by'] as String),
      changedAt: DateTime.parse(row['changed_at'] as String),
    );
  }
}

class HospitalIsolationArea {
  HospitalIsolationArea({
    required this.id,
    required this.stayId,
    required this.cage,
    required this.patientName,
    required this.reference,
    required this.steps,
    required this.exposedAt,
    required this.releasedAt,
  });
  final String id, stayId, patientName, reference;
  final String? cage;
  final List<String> steps;
  final DateTime exposedAt;
  final DateTime? releasedAt;
  bool get ready => releasedAt != null;
  String get cageLabel => cage ?? 'Área sin jaula asignada';
  /// Reads an exposed area that has not been marked cleaned for [clinic].
  ///
  /// A release timestamp makes the area ready for cleaning confirmation.
  /// Throws [FormatException] for a clinic mismatch, an already cleaned area,
  /// or invalid text, checklist, or timestamps; incorrect types cause type errors.
  factory HospitalIsolationArea.read(Map<String, dynamic> row, String clinic) {
    if (row['clinic_id'] != clinic || row['cleaned_at'] != null) {
      throw const FormatException('Área de aislamiento no disponible.');
    }
    return HospitalIsolationArea(
      id: hospitalText(row['id'] as String),
      stayId: hospitalText(row['stay_id'] as String),
      cage: row['cage'] as String?,
      patientName: row['patient_name'] as String,
      reference: hospitalText(row['protocol_reference'] as String, max: 1000),
      steps: isolationSteps((row['steps'] as List).cast<String>()),
      exposedAt: DateTime.parse(row['exposed_at'] as String),
      releasedAt: row['released_at'] == null
          ? null
          : DateTime.parse(row['released_at'] as String),
    );
  }
}

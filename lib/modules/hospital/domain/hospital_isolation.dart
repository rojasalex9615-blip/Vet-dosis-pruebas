import 'hospital_models.dart';

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

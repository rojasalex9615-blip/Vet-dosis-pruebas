import '../../doses/domain/quantity.dart';
import '../../forms/clinical/clinical_models.dart' show clinicalInstant;

const careResultKinds = {
  'feeding': 'Alimentación',
  'catheter_review': 'Revisión de catéter',
  'equipment_change': 'Cambio de equipo',
  'other': 'Otro cuidado / revisión',
};

Map<String, dynamic> validateCareResult(Map<String, dynamic> data) {
  String text(String key, int max) {
    final raw = data[key];
    if (raw is! String || raw.trim().isEmpty || raw.length > max) {
      throw FormatException('Completa $key (máximo $max caracteres).');
    }
    return raw.trim();
  }

  final kind = text('care_kind', 40);
  if (!careResultKinds.containsKey(kind) || data['confirmed'] != true) {
    throw const FormatException(
      'Selecciona el cuidado y confirma que lo realizaste.',
    );
  }
  String? offered, consumed, unit;
  if (kind == 'feeding') {
    offered = text('offered', 40).replaceAll(',', '.');
    consumed = text('consumed', 40).replaceAll(',', '.');
    final amount = Quantity.parse(offered), taken = Quantity.parse(consumed);
    if (!amount.positive || taken.compareTo(amount) > 0) {
      throw const FormatException(
        'La cantidad ofrecida debe ser mayor que cero; el consumo no puede superarla.',
      );
    }
    unit = text('unit', 20);
    if (!['g', 'ml', 'porción'].contains(unit)) {
      throw const FormatException('Selecciona la unidad de ambas cantidades.');
    }
  } else if (['offered', 'consumed', 'unit'].any(data.containsKey)) {
    throw const FormatException(
      'Las cantidades corresponden solo a alimentación.',
    );
  }
  return {
    'care_kind': kind,
    'findings': text('findings', 4000),
    'observed_at': clinicalInstant(text('observed_at', 40)).toIso8601String(),
    'confirmed': true,
    'offered': ?offered,
    'consumed': ?consumed,
    'unit': ?unit,
    if (data['replaces_id'] != null) 'replaces_id': text('replaces_id', 36),
    if (data['replaces_id'] != null)
      'correction_reason': text('correction_reason', 1000),
  };
}

class HospitalCareWorkspace {
  HospitalCareWorkspace._(
    this.task,
    this.records,
    this.canRecord,
    this.canCorrect,
  );
  final Map<String, dynamic>? task;
  final List<Map<String, dynamic>> records;
  final bool canRecord, canCorrect;
  factory HospitalCareWorkspace.read(
    Map<String, dynamic> raw,
    String clinic,
    String actor,
    String? taskId,
  ) {
    if (raw['schema_version'] != 1 ||
        raw['clinic_id'] != clinic ||
        raw['actor_id'] != actor ||
        raw['task_id'] != taskId ||
        raw['actions'] is! Map ||
        raw['actions']['record'] is! bool ||
        raw['actions']['correct'] is! bool ||
        raw['records'] is! List ||
        (taskId == null
            ? raw['task'] != null ||
                  raw['actions']['record'] == true ||
                  raw['actions']['correct'] == true
            : raw['task'] is! Map)) {
      throw const FormatException(
        'Contrato de resultados de cuidados desconocido.',
      );
    }
    final task = raw['task'] == null
        ? null
        : Map<String, dynamic>.from(raw['task'] as Map);
    if (task != null &&
        (task['id'] != taskId ||
            task['clinic_id'] != clinic ||
            task['version'] is! int ||
            task['version'] < 1 ||
            [
              'patient_id',
              'patient_name',
              'label',
              'instructions',
            ].any((k) => task[k] is! String))) {
      throw const FormatException('Tarea de otra clínica o incompleta.');
    }
    final records = (raw['records'] as List).map((r) {
      if (r is! Map ||
          r['clinic_id'] != clinic ||
          (taskId != null &&
              (r['task_id'] != taskId ||
                  r['patient_id'] != task!['patient_id'])) ||
          [
            'id',
            'task_id',
            'actor_id',
            'findings',
            'patient_id',
            'patient_name',
            'task_label',
            'observed_at',
            'created_at',
          ].any((k) => r[k] is! String) ||
          DateTime.tryParse(r['observed_at']) == null ||
          DateTime.tryParse(r['created_at']) == null ||
          !careResultKinds.containsKey(r['care_kind']) ||
          (r['replaces_id'] != null &&
              (r['replaces_id'] is! String ||
                  r['correction_reason'] is! String))) {
        throw const FormatException(
          'Resultado de cuidado incompleto o fuera de alcance.',
        );
      }
      final result = Map<String, dynamic>.from(r);
      // Reuse exact validation; PostgreSQL read timestamps may use +00:00.
      validateCareResult({
        'care_kind': result['care_kind'],
        'findings': result['findings'],
        'confirmed': true,
        'observed_at': DateTime.parse(
          result['observed_at'],
        ).toUtc().toIso8601String(),
        if (result['offered'] != null) 'offered': result['offered'],
        if (result['consumed'] != null) 'consumed': result['consumed'],
        if (result['unit'] != null) 'unit': result['unit'],
      });
      return result;
    }).toList();
    return HospitalCareWorkspace._(
      task,
      records,
      raw['actions']['record'],
      raw['actions']['correct'],
    );
  }
  bool replaced(String id) => records.any((r) => r['replaces_id'] == id);
}

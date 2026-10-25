import 'hospital_models.dart' show hospitalText;

/// Normalizes a confirmed daily order into fields accepted by the scheduling RPC.
///
/// Accepts integer `minutes` since midnight or comma-separated HH:mm `times`;
/// returns sorted, distinct minutes for 1 to 31 inclusive days, at most 200
/// tasks, and an escalation delay of 1 to 120 minutes. Throws [FormatException]
/// for invalid fields or a replacement without a change reason. Time zone
/// existence and whether instants are in the future are checked by the server.
Map<String, dynamic> validateDailyOrder(Map<String, dynamic> data) {
  String text(String k, int max) =>
      hospitalText(data[k] is String ? data[k] as String : '', max: max);
  final first = text('first_day', 10), last = text('last_day', 10);
  DateTime date(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      throw const FormatException('Usa fechas AAAA-MM-DD.');
    }
    final parsed = DateTime.tryParse('${s}T00:00:00Z');
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != s) {
      throw const FormatException('Fecha inválida.');
    }
    return parsed;
  }

  final days = date(last).difference(date(first)).inDays + 1;
  final raw = data['minutes'];
  final List<int> minutes;
  if (raw is List && raw.every((m) => m is int)) {
    minutes = raw.cast<int>().toList();
  } else {
    if (raw != null) {
      throw const FormatException('Los horarios deben ser minutos enteros.');
    }
    final times = text('times', 2000).split(',').map((s) => s.trim());
    minutes = times.map((s) {
      if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(s)) {
        throw const FormatException('Usa horarios HH:mm separados por comas.');
      }
      final p = s.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }).toList();
  }
  if (days < 1 ||
      days > 31 ||
      minutes.isEmpty ||
      minutes.length * days > 200 ||
      minutes.any((m) => m < 0 || m > 1439) ||
      minutes.toSet().length != minutes.length) {
    throw const FormatException(
      'Revisa fechas y horarios: máximo 31 días, 200 tareas y sin horarios repetidos.',
    );
  }
  final escalation = int.tryParse('${data['escalation_minutes']}');
  if (data['confirmed'] != true ||
      escalation == null ||
      escalation < 1 ||
      escalation > 120) {
    throw const FormatException(
      'Revisa la orden y captura de 1 a 120 minutos para escalar el aviso.',
    );
  }
  minutes.sort();
  return {
    'procedure_id': text('procedure_id', 100),
    'label': text('label', 300),
    'instructions': text('instructions', 4000),
    'first_day': first,
    'last_day': last,
    'zone': text('zone', 100),
    'minutes': minutes,
    'escalation_minutes': escalation,
    'confirmed': true,
    if (data['replaces_id'] != null) 'replaces_id': text('replaces_id', 36),
    if (data['replaces_id'] != null)
      'change_reason': text('change_reason', 1000),
  };
}

class HospitalAutomationWorkspace {
  HospitalAutomationWorkspace._(this.raw);
  final Map<String, dynamic> raw;
  bool get enabled => raw['runtime']['enabled'] == true;
  bool get canCreate => raw['actions']['create'] == true;
  bool get canManage => raw['actions']['manage'] == true;
  List<Map<String, dynamic>> rows(String key) => (raw[key] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  /// Reads a version 1 workspace for the expected clinic, actor, and stay.
  ///
  /// A null [stay] selects the clinic overview. Throws [FormatException] for
  /// rejected scope, orders, notices, or action flags; malformed runtime types
  /// can also cause type errors.
  factory HospitalAutomationWorkspace.read(
    Map<String, dynamic> raw,
    String clinic,
    String actor,
    String? stay,
  ) {
    Never invalid() => throw const FormatException(
      'Contrato de órdenes y avisos desconocido o fuera de alcance.',
    );
    if (raw['schema_version'] != 1 ||
        raw['clinic_id'] != clinic ||
        raw['actor_id'] != actor ||
        raw['stay_id'] != stay ||
        raw['runtime'] is! Map ||
        raw['runtime']['enabled'] is! bool ||
        raw['actions'] is! Map ||
        ['create', 'manage'].any((k) => raw['actions'][k] is! bool)) {
      invalid();
    }
    if (raw['actions']['create'] == true &&
        (stay == null || raw['runtime']['enabled'] != true)) {
      invalid();
    }
    for (final key in ['orders', 'notices', 'members', 'procedures']) {
      if (raw[key] is! List ||
          (raw[key] as List).any((r) => r is! Map || r['id'] is! String)) {
        invalid();
      }
    }
    if (raw['route'] != null &&
        (raw['route'] is! Map ||
            raw['route']['primary_user'] is! String ||
            raw['route']['mvz_user'] is! String)) {
      invalid();
    }
    for (final r in raw['orders']) {
      if (r['clinic_id'] != clinic ||
          (stay != null && r['stay_id'] != stay) ||
          r['can_stop'] is! bool ||
          r['version'] is! int ||
          r['version'] < 1 ||
          [
            'patient_name',
            'author_id',
            'created_at',
          ].any((k) => r[k] is! String) ||
          DateTime.tryParse(r['created_at']) == null) {
        invalid();
      }
      validateDailyOrder({...Map<String, dynamic>.from(r), 'confirmed': true});
      if (r['stop'] != null &&
          (r['stop'] is! Map ||
              r['stop']['order_id'] != r['id'] ||
              r['stop']['clinic_id'] != clinic ||
              r['stop']['reason'] is! String)) {
        invalid();
      }
    }
    for (final r in raw['notices']) {
      if (r['clinic_id'] != clinic ||
          (stay != null && r['stay_id'] != stay) ||
          !['primary', 'mvz'].contains(r['stage']) ||
          !['pending', 'done', 'cancelled'].contains(r['task_state']) ||
          r['can_ack'] is! bool ||
          [
            'recipient_id',
            'task_id',
            'patient_name',
            'task_label',
            'due_at',
            'created_at',
          ].any((k) => r[k] is! String) ||
          DateTime.tryParse(r['due_at']) == null ||
          DateTime.tryParse(r['created_at']) == null ||
          (r['can_ack'] == true && r['recipient_id'] != actor)) {
        invalid();
      }
      final a = r['response'];
      if (a != null &&
          (a is! Map ||
              a['notice_id'] != r['id'] ||
              a['clinic_id'] != clinic ||
              a['actor_id'] != r['recipient_id'] ||
              a['note'] is! String ||
              a['created_at'] is! String ||
              DateTime.tryParse(a['created_at']) == null)) {
        invalid();
      }
    }
    for (final r in raw['members']) {
      if (r['name'] is! String ||
          r['primary_eligible'] is! bool ||
          r['mvz_eligible'] is! bool) {
        invalid();
      }
    }
    for (final r in raw['procedures']) {
      if (r['name'] is! String) invalid();
    }
    return HospitalAutomationWorkspace._(raw);
  }
}

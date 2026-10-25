abstract interface class HospitalHistoryRepository {
  /// Reads up to 25 discharged stays, newest discharge first.
  ///
  /// [query] is a patient name substring of at most 100 characters; empty means
  /// all patients. Pass the prior page's `next` as [before], or null to start.
  Future<HospitalHistoryPage> closedHistory(
    String clinic,
    String query,
    Map<String, dynamic>? before,
  );
  /// Reads a discharged stay, location events, and up to 50 tasks, earliest first.
  ///
  /// Pass the prior detail's `next` as [before] to read later tasks, or null to
  /// start. Historical tasks expose no action permissions.
  Future<HospitalHistoryDetail> closedDetail(
    String clinic,
    String stay,
    Map<String, dynamic>? before,
  );
}

Never _invalid() => throw const FormatException(
  'Historial hospitalario desconocido o fuera de alcance.',
);
Map<String, dynamic>? _cursor(Object? value) {
  if (value == null) return null;
  if (value is! Map ||
      value.length != 2 ||
      value['id'] is! String ||
      value['at'] is! String ||
      DateTime.tryParse(value['at'] as String) == null) {
    _invalid();
  }
  return Map<String, dynamic>.from(value);
}

void _envelope(Map<String, dynamic> raw, String clinic, String actor) {
  if (raw['version'] != 1 ||
      raw['clinic_id'] != clinic ||
      raw['actor_id'] != actor) {
    _invalid();
  }
}

List<Map<String, dynamic>> _rows(Object? raw) {
  if (raw is! List || raw.any((r) => r is! Map)) _invalid();
  return raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
}

void _stay(Map<String, dynamic> row, String clinic) {
  if (row['clinic_id'] != clinic ||
      [
        'id',
        'patient_id',
        'patient_name',
        'species',
      ].any((k) => row[k] is! String) ||
      ['admitted_at', 'discharged_at'].any(
        (k) => row[k] is! String || DateTime.tryParse(row[k] as String) == null,
      )) {
    _invalid();
  }
}

class HospitalHistoryPage {
  HospitalHistoryPage(this.stays, this.next);
  final List<Map<String, dynamic>> stays;
  final Map<String, dynamic>? next;
  /// Validates a history page against the expected clinic, actor, and query.
  ///
  /// Throws [FormatException] for invalid scope, stays, page size, or a cursor
  /// that does not match the last row. Incorrect map key types can propagate
  /// type errors.
  factory HospitalHistoryPage.read(
    Map<String, dynamic> raw,
    String clinic,
    String actor,
    String query,
  ) {
    _envelope(raw, clinic, actor);
    if (raw['query'] != query) _invalid();
    final rows = _rows(raw['stays']);
    if (rows.length > 25) _invalid();
    for (final row in rows) {
      _stay(row, clinic);
    }
    final next = _cursor(raw['next']);
    if (next != null &&
        (rows.length != 25 ||
            next['id'] != rows.last['id'] ||
            next['at'] != rows.last['discharged_at'])) {
      _invalid();
    }
    return HospitalHistoryPage(rows, next);
  }
}

class HospitalHistoryDetail {
  HospitalHistoryDetail(this.stay, this.tasks, this.events, this.next);
  final Map<String, dynamic> stay;
  final List<Map<String, dynamic>> tasks, events;
  final Map<String, dynamic>? next;
  /// Validates a discharged stay, task page, events, and continuation cursor.
  ///
  /// Requires the expected clinic, actor, and stay, with no task action fields.
  /// Throws [FormatException] for rejected data; incorrect map key types can
  /// propagate type errors.
  factory HospitalHistoryDetail.read(
    Map<String, dynamic> raw,
    String clinic,
    String actor,
    String stayId,
  ) {
    _envelope(raw, clinic, actor);
    if (raw['stay_id'] != stayId || raw['stay'] is! Map) _invalid();
    final stay = Map<String, dynamic>.from(raw['stay'] as Map);
    _stay(stay, clinic);
    if (stay['id'] != stayId) _invalid();
    final tasks = _rows(raw['tasks']), events = _rows(raw['events']);
    if (tasks.length > 50) _invalid();
    for (final t in tasks) {
      if (t['clinic_id'] != clinic ||
          t['stay_id'] != stayId ||
          ['id', 'label', 'instructions'].any((k) => t[k] is! String) ||
          !['pending', 'done', 'cancelled'].contains(t['state']) ||
          !['medicacion', 'revision'].contains(t['kind']) ||
          t['due_at'] is! String ||
          DateTime.tryParse(t['due_at'] as String) == null ||
          t.containsKey('actions')) {
        _invalid();
      }
    }
    for (final e in events) {
      if (![
            'hospital_admitted',
            'hospital_cage_changed',
          ].contains(e['action']) ||
          e['at'] is! String ||
          DateTime.tryParse(e['at'] as String) == null ||
          e['details'] is! Map) {
        _invalid();
      }
    }
    final next = _cursor(raw['next']);
    if (next != null &&
        (tasks.length != 50 ||
            next['id'] != tasks.last['id'] ||
            next['at'] != tasks.last['due_at'])) {
      _invalid();
    }
    return HospitalHistoryDetail(stay, tasks, events, next);
  }
}

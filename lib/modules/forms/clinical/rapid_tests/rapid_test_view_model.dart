import 'package:flutter/foundation.dart';
import '../../../auth/domain/clinic_membership.dart';
import '../clinical_models.dart';
import 'rapid_test_repository.dart';

class RapidTestViewModel extends ChangeNotifier {
  RapidTestViewModel(this.repository, this.member, this.caseData);
  final RapidTestRepository repository;
  final ClinicMembership member;
  final ClinicalCase caseData;
  Map<String, dynamic>? snapshot;
  bool busy = false, _disposed = false;
  int _generation = 0;
  String? error;
  bool can(String action) =>
      !busy && error == null && snapshot?['actions']?[action] == true;
  List<Map<String, dynamic>> get records =>
      (snapshot?['records'] as List? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  bool replaced(String id) => records.any((r) => r['replaces_id'] == id);

  void validate(Map<String, dynamic> value) {
    if (value['schema_version'] != 1 ||
        value['clinic_id'] != member.clinicId ||
        value['case_id'] != caseData.id ||
        value['patient_id'] != caseData.patientId ||
        value['actor_id'] != member.userId ||
        value['actions'] is! Map ||
        [
          'record',
          'correct',
          'photo',
        ].any((k) => value['actions'][k] is! bool) ||
        value['records'] is! List) {
      throw StateError('unknown_rapid_test_workspace');
    }
    for (final row in value['records'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          row['case_id'] != caseData.id ||
          row['clinic_id'] != member.clinicId ||
          row['recorded_by'] is! String ||
          [
            'test_name',
            'result',
            'sample',
            'interpretation',
            'notes',
            'created_at',
            'observed_at',
          ].any((k) => row[k] is! String) ||
          DateTime.tryParse(row['created_at']) == null ||
          DateTime.tryParse(row['observed_at']) == null ||
          !rapidBandLabels.containsKey(row['c_band']) ||
          !rapidBandLabels.containsKey(row['t_band']) ||
          (row['photo_path'] != null &&
              (row['photo_path'] is! String ||
                  !(row['photo_path'] as String).startsWith(
                    '${member.clinicId}/${caseData.id}/',
                  )))) {
        throw StateError('unknown_rapid_test_record');
      }
    }
  }

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_generation;
    busy = true;
    snapshot = null;
    error = null;
    notifyListeners();
    try {
      final value = await repository.workspace(caseData.id);
      if (_disposed || generation != _generation) return;
      validate(value);
      snapshot = value;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      error =
          'No se pudieron consultar las pruebas. Revisa conexión, permisos y versión del servidor.';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> add(
    Map<String, dynamic> data,
    String operation, {
    RapidTestPhoto? photo,
  }) async {
    final payload = validateRapidTest(data);
    await load();
    if (!can(payload.containsKey('replaces_id') ? 'correct' : 'record') ||
        (photo != null && !can('photo')) ||
        (payload['replaces_id'] != null &&
            (replaced(payload['replaces_id']) ||
                !records.any((r) => r['id'] == payload['replaces_id'])))) {
      throw StateError('rapid_test_access_changed');
    }
    await repository.add(caseData.id, payload, operation, photo: photo);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    snapshot = null;
    super.dispose();
  }
}

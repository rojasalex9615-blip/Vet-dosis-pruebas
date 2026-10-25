import 'package:flutter/foundation.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../forms/clinical/clinical_models.dart';
import '../../forms/clinical/clinical_repository.dart';
import '../../forms/clinical/clinical_view_model.dart';
import '../../patients/domain/recorded_weight.dart';
import '../domain/hospital_models.dart';
import '../domain/hospital_repository.dart';

class HospitalWeightViewModel extends ChangeNotifier {
  HospitalWeightViewModel(
    this.repository,
    this.hospital,
    this.member,
    this.stay, {
    DateTime Function()? now,
    bool Function()? contextIsCurrent,
  }) : now = now ?? DateTime.now,
       contextIsCurrent = contextIsCurrent ?? (() => true),
       gate = ClinicalViewModel(repository, member.clinicId, stay.patientId);

  final ClinicalRepository repository;
  final HospitalRepository hospital;
  final ClinicMembership member;
  final HospitalStay stay;
  final DateTime Function() now;
  final bool Function() contextIsCurrent;
  final ClinicalViewModel gate;
  List<ClinicalCase> cases = [];
  List<RecordedPatientWeight> weights = [];
  String? selectedCaseId, error;
  bool busy = false, _disposed = false;
  int _generation = 0;
  bool get canRecord =>
      !busy && error == null && selectedCaseId != null && gate.can('observe');
  bool get hasWeightToday => weights.any((w) {
    final date = w.observedAt.toLocal();
    final today = now().toLocal();
    return date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
  });

  void changed() {
    if (!_disposed) notifyListeners();
  }

  void clear() {
    cases = [];
    weights = [];
    gate.cases = [];
    gate.selected = null;
    gate.workspace = null;
  }

  /// Rechecks that this patient's matching admission remains in the active sheet.
  ///
  /// Throws [StateError] for a changed context, disposal after loading, or a
  /// missing matching stay. Repository errors propagate.
  Future<void> checkStay() async {
    if (!contextIsCurrent() || stay.clinicId != member.clinicId) {
      throw StateError('wrong_clinic');
    }
    final snapshot = await hospital.load(member.clinicId);
    if (_disposed ||
        !contextIsCurrent() ||
        !snapshot.stays.any(
          (s) =>
              s.id == stay.id &&
              s.clinicId == member.clinicId &&
              s.patientId == stay.patientId &&
              s.admittedAt == stay.admittedAt,
        )) {
      throw StateError('active_matching_stay_required');
    }
  }

  /// Throws [StateError] unless the case matches this clinic and patient, and
  /// [expectedId] when supplied.
  void checkCase(ClinicalCase c, {String? expectedId}) {
    if (c.data['clinic_id'] != member.clinicId ||
        c.patientId != stay.patientId ||
        (expectedId != null && c.id != expectedId)) {
      throw StateError('matching_clinic_patient_case_required');
    }
  }

  /// Refreshes readable cases and the selected detail using explicit permissions.
  ///
  /// A null [caseId] loads no detail. Throws [StateError] for missing or rejected
  /// permissions, changed context, disposal, or mismatched cases. Repository
  /// errors propagate; successful reads replace the clinical gate's state.
  Future<void> readClinical(String? caseId) async {
    if (repository is! ClinicalPermissionRepository) {
      throw StateError('explicit_contract_required');
    }
    final contract = await (repository as ClinicalPermissionRepository)
        .workspace(member.clinicId, caseId);
    if (_disposed || !contextIsCurrent() || contract == null) {
      throw StateError('explicit_clinical_read_required');
    }
    gate.validateWorkspace(contract, caseId);
    if (contract['can_read'] != true) throw StateError('clinical_read_denied');
    final available = await repository.cases(member.clinicId, stay.patientId);
    if (_disposed || !contextIsCurrent()) throw StateError('context_changed');
    for (final c in available) {
      checkCase(c);
    }
    if (caseId != null && !available.any((c) => c.id == caseId)) {
      throw StateError('case_not_available');
    }
    final detail = caseId == null ? null : await repository.bundle(caseId);
    if (_disposed || !contextIsCurrent()) throw StateError('context_changed');
    if (detail != null) checkCase(detail.caseData, expectedId: caseId);
    gate.cases = available;
    gate.selected = detail;
    gate.workspace = contract;
    gate.permissionsKnown = true;
    gate.error = null;
  }

  /// Loads unreplaced kg measurements across all readable cases for this patient.
  ///
  /// Includes observation times from admission through [now], newest first.
  /// A null [caseId] leaves no case selected for recording. Read or validation
  /// failures clear displayed data and set [error] instead of propagating.
  /// Calls while busy or disposed do nothing.
  Future<void> load({String? caseId}) async {
    if (_disposed || busy) return;
    final request = ++_generation;
    selectedCaseId = caseId;
    busy = true;
    error = null;
    clear();
    changed();
    try {
      await checkStay();
      if (_disposed || request != _generation) return;
      await readClinical(caseId);
      if (_disposed || request != _generation) return;
      final available = List<ClinicalCase>.of(gate.cases);
      final bundles = <ClinicalBundle>[];
      // Bound concurrent chart requests, while retaining every authorized case.
      for (var offset = 0; offset < available.length; offset += 4) {
        final group = available.skip(offset).take(4);
        bundles.addAll(
          await Future.wait(
            group.map((c) async {
              final bundle = c.id == caseId
                  ? gate.selected!
                  : await repository.bundle(c.id);
              checkCase(bundle.caseData, expectedId: c.id);
              return bundle;
            }),
          ),
        );
        if (_disposed || request != _generation) return;
      }
      final current = <RecordedPatientWeight>[];
      for (final bundle in bundles) {
        final replaced = bundle.observations
            .map((r) => r['replaces_id'])
            .whereType<String>()
            .toSet();
        for (final row in bundle.observations.where(
          (r) => r['kind'] == 'weight' && !replaced.contains(r['id']),
        )) {
          if (row['clinic_id'] != member.clinicId ||
              row['case_id'] != bundle.caseData.id ||
              row['unit'] != 'kg') {
            throw StateError('matching_weight_required');
          }
          final at = recordedWeightInstant(row['observed_at'] as String);
          if (at.isBefore(stay.admittedAt) || at.isAfter(now())) continue;
          current.add(
            RecordedPatientWeight(
              id: row['id'] as String,
              clinicId: member.clinicId,
              patientId: stay.patientId,
              patientName: stay.patientName,
              caseId: bundle.caseData.id,
              kg: clinicalNumber(row['value'] as String, 'weight'),
              observedAt: at,
              performedBy: row['performed_by'] as String,
              recordedBy: row['recorded_by'] as String,
              recordedAt: recordedWeightInstant(row['created_at'] as String),
            ),
          );
        }
      }
      current.sort((a, b) {
        final time = b.observedAt.compareTo(a.observedAt);
        return time != 0 ? time : b.recordedAt.compareTo(a.recordedAt);
      });
      if (_disposed || request != _generation) return;
      if (!contextIsCurrent()) throw StateError('context_changed');
      cases = List.unmodifiable(available);
      weights = List.unmodifiable(current);
    } catch (_) {
      if (!_disposed && request == _generation) {
        clear();
        error =
            'No se pudo comprobar el peso. Revisa acceso, estancia activa y conexión.';
      }
    } finally {
      if (!_disposed && request == _generation) {
        busy = false;
        changed();
      }
    }
  }

  /// Records the current user's measured weight in kilograms in the selected case.
  ///
  /// [observed] must be a UTC timestamp with seconds and a trailing Z, from
  /// admission through [now]. Reuse [operation] for an identical retry.
  /// Throws [FormatException] for invalid input or unavailable selection.
  /// Stay, permission, and write failures clear data, set [error], and are
  /// converted to [FormatException]. Success does not reload displayed weights.
  Future<void> record(
    String value,
    String observed,
    String notes,
    String operation,
  ) async {
    if (_disposed || busy || selectedCaseId == null) {
      throw const FormatException(
        'Selecciona un caso y actualiza sus permisos.',
      );
    }
    final caseId = selectedCaseId!;
    final at = clinicalInstant(observed);
    if (at.isBefore(stay.admittedAt) || at.isAfter(now())) {
      throw const FormatException(
        'La medición debe estar entre el ingreso y la hora actual.',
      );
    }
    final payload = validateObservation({
      'kind': 'weight',
      'value': value,
      'unit': 'kg',
      'observed_at': observed,
      'performed_by': member.userId,
      'notes': notes,
    });
    busy = true;
    changed();
    try {
      await checkStay();
      await readClinical(caseId);
      if (_disposed || !contextIsCurrent() || !gate.can('observe')) {
        throw StateError('observation_permission_required');
      }
      await repository.observation(caseId, payload, operation);
    } catch (_) {
      if (!_disposed) {
        clear();
        error =
            'No se confirmó el guardado. Actualiza para comprobarlo antes de repetirlo.';
      }
      throw const FormatException(
        'No se confirmó el guardado. Revisa la hoja y los permisos antes de repetirlo.',
      );
    } finally {
      if (!_disposed) {
        busy = false;
        changed();
      }
    }
  }

  /// Reloads weights and checks that the same measurement is still available.
  ///
  /// Returns false while busy or disposed, for a scope mismatch, or when a
  /// refresh fails or no longer includes the exact measurement.
  Future<bool> validateWeight(RecordedPatientWeight weight) async {
    if (_disposed ||
        busy ||
        weight.clinicId != member.clinicId ||
        weight.patientId != stay.patientId) {
      return false;
    }
    await load(caseId: selectedCaseId);
    return !_disposed &&
        contextIsCurrent() &&
        error == null &&
        weights.any((w) => w.sameMeasurement(weight));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    clear();
    gate.dispose();
    super.dispose();
  }
}

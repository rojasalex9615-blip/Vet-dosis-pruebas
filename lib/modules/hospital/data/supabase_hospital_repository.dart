import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/hospital_models.dart';
import '../domain/hospital_care_result.dart';
import '../domain/hospital_automation.dart';
import '../domain/hospital_isolation.dart';
import '../domain/hospital_repository.dart';

class SupabaseHospitalRepository
    implements
        HospitalRepository,
        HospitalLocationRepository,
        HospitalReviewRepository,
        HospitalResolutionRepository,
        HospitalIsolationRepository,
        HospitalCareResultRepository,
        HospitalAutomationRepository {
  SupabaseHospitalRepository(this.client);
  final SupabaseClient client;
  @override
  Future<HospitalSnapshot> load(String clinicId) async {
    final raw =
        await client.rpc('hospital_snapshot', params: {'p_clinic_id': clinicId})
            as Map;
    final dutyVersion = (raw['capabilities'] as Map?)?['duty_routing_version'];
    if (dutyVersion != null && dutyVersion != 1) {
      throw const FormatException('Versión de turnos desconocida.');
    }
    final automationVersion =
        (raw['capabilities'] as Map?)?['automation_version'];
    if (automationVersion != null && automationVersion != 1) {
      throw const FormatException('Versión de automatización desconocida.');
    }
    final careVersion = (raw['capabilities'] as Map?)?['care_results_version'];
    if (careVersion != null && careVersion != 1) {
      throw const FormatException(
        'Versión de resultados de cuidados desconocida.',
      );
    }
    final isolationVersion =
        (raw['capabilities'] as Map?)?['isolation_version'];
    if (isolationVersion != null && isolationVersion != 1) {
      throw const FormatException('Versión de aislamiento desconocida.');
    }
    if (isolationVersion == 1 &&
        (raw['isolations'] is! List ||
            raw['isolation_areas'] is! List ||
            raw['permissions'] is! Map ||
            raw['permissions']['hospital.isolation.manage'] is! bool ||
            raw['permissions']['hospital.isolation.handle'] is! bool)) {
      throw const FormatException('Contrato de aislamiento incompleto.');
    }
    return HospitalSnapshot(
      (raw['stays'] as List)
          .map((r) => HospitalStay.read(Map<String, dynamic>.from(r as Map)))
          .toList(),
      (raw['tasks'] as List)
          .map((r) => HospitalTask.read(Map<String, dynamic>.from(r as Map)))
          .toList(),
      dutyRouting: dutyVersion == 1,
      careResultsEnabled: careVersion == 1,
      automationEnabled: automationVersion == 1,
      isolationEnabled: isolationVersion == 1,
      isolations: isolationVersion != 1
          ? const []
          : (raw['isolations'] as List)
                .map(
                  (r) => HospitalIsolation.read(
                    Map<String, dynamic>.from(r as Map),
                    clinicId,
                  ),
                )
                .toList(),
      isolationAreas: isolationVersion != 1
          ? const []
          : (raw['isolation_areas'] as List)
                .map(
                  (r) => HospitalIsolationArea.read(
                    Map<String, dynamic>.from(r as Map),
                    clinicId,
                  ),
                )
                .toList(),
      reviewedDischarge:
          (raw['capabilities'] as Map?)?['reviewed_discharge'] == true,
      medicationFollowup:
          (raw['capabilities'] as Map?)?['medication_followup'] == true,
      typedReviews: (raw['capabilities'] as Map?)?['typed_reviews'] == true,
      reviewTypes: ((raw['review_types'] as List?) ?? [])
          .map(
            (r) => HospitalReviewType(r['id'] as String, r['name'] as String),
          )
          .toList(),
      optionalCage: (raw['capabilities'] as Map?)?['optional_cage'] == true,
      cageChanges: (raw['capabilities'] as Map?)?['cage_changes'] == true,
      permissions: raw['permissions'] is Map
          ? Map<String, dynamic>.from(raw['permissions'] as Map)
          : null,
    );
  }

  @override
  Future<Map<String, dynamic>> automationWorkspace(
    String clinic,
    String? stay,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
          'hospital_automation_workspace',
          params: {'p_clinic': clinic, 'p_stay': stay},
        )
        as Map,
  );
  @override
  Future<void> createDailyOrder(
    String clinic,
    String stay,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'hospital_daily_order_create',
      params: {
        'p_clinic': clinic,
        'p_stay': stay,
        'p_data': validateDailyOrder(data),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> stopDailyOrder(
    String clinic,
    String order,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'hospital_daily_order_stop',
      params: {
        'p_clinic': clinic,
        'p_order': order,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> setNoticeRoute(
    String clinic,
    String primary,
    String mvz,
    String operation,
  ) async {
    await client.rpc(
      'hospital_notice_route_set',
      params: {
        'p_clinic': clinic,
        'p_primary': primary,
        'p_mvz': mvz,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> acknowledgeNotice(
    String clinic,
    String notice,
    String note,
    String operation,
  ) async {
    await client.rpc(
      'hospital_notice_ack',
      params: {
        'p_clinic': clinic,
        'p_notice': notice,
        'p_note': note,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> careWorkspace(
    String clinic,
    String? task,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
          'hospital_care_workspace',
          params: {'p_clinic': clinic, 'p_task': task},
        )
        as Map,
  );
  @override
  Future<void> recordCare(
    String clinic,
    String task,
    int version,
    Map<String, dynamic> data,
    String operation,
  ) async {
    await client.rpc(
      'hospital_care_record',
      params: {
        'p_clinic': clinic,
        'p_task': task,
        'p_version': version,
        'p_data': validateCareResult(data),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> setIsolation(
    String clinic,
    HospitalStay stay,
    bool active,
    String reason,
    String reference,
    List<String> steps,
    String operation,
  ) async {
    await client.rpc(
      'hospital_isolation_set',
      params: {
        'p_clinic': clinic,
        'p_stay': stay.id,
        'p_version': stay.version,
        'p_active': active,
        'p_reason': hospitalText(reason, max: 1000),
        'p_reference': hospitalText(reference, max: 1000),
        'p_steps': isolationSteps(steps),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> enterIsolation(
    String clinic,
    HospitalStay stay,
    String note,
    String operation,
  ) async {
    await client.rpc(
      'hospital_isolation_enter',
      params: {
        'p_clinic': clinic,
        'p_stay': stay.id,
        'p_version': stay.version,
        'p_note': hospitalText(note, max: 1000),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> cleanIsolation(
    String clinic,
    HospitalIsolationArea area,
    List<String> checks,
    String notes,
    String operation,
  ) async {
    if (!area.ready ||
        checks.length != area.steps.length ||
        List.generate(
          checks.length,
          (i) => checks[i] == area.steps[i],
        ).contains(false)) {
      throw const FormatException(
        'Confirma todos los pasos del área liberada.',
      );
    }
    await client.rpc(
      'hospital_isolation_clean',
      params: {
        'p_clinic': clinic,
        'p_area': area.id,
        'p_checks': checks,
        'p_notes': hospitalText(notes, max: 1000, allowEmpty: true),
        'p_operation': operation,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> isolationHistory(
    String clinic,
    String? stay,
  ) async =>
      (await client.rpc(
                'hospital_isolation_history',
                params: {'p_clinic': clinic, 'p_stay': stay},
              )
              as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

  @override
  Future<void> followup(
    String clinic,
    HospitalTask task,
    String action,
    int? minutes,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'hospital_medication_followup',
      params: {
        'p_clinic': clinic,
        'p_task': task.id,
        'p_version': task.version,
        'p_action': action,
        'p_minutes': minutes,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<HospitalDischargePreview> dischargePreview(
    String clinic,
    HospitalStay stay,
  ) async => HospitalDischargePreview.read(
    Map<String, dynamic>.from(
      await client.rpc(
            'hospital_discharge_preview',
            params: {'p_clinic': clinic, 'p_stay': stay.id},
          )
          as Map,
    ),
  );
  @override
  Future<void> confirmDischarge(
    String clinic,
    HospitalStay stay,
    HospitalDischargePreview preview,
    String reason,
    String operation,
  ) async {
    if (preview.stayId != stay.id) {
      throw const FormatException('Estancia distinta.');
    }
    await client.rpc(
      'hospital_discharge_confirm',
      params: {
        'p_clinic': clinic,
        'p_stay': stay.id,
        'p_version': preview.version,
        'p_pending_hash': preview.hash,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> admit(
    String clinicId,
    String patientId,
    String cage,
    String operationId,
  ) async {
    await client.rpc(
      'hospital_admit',
      params: {
        'p_clinic_id': clinicId,
        'p_patient_id': patientId,
        'p_cage': cage,
        'p_operation_id': operationId,
      },
    );
  }

  @override
  Future<void> prescribe(
    String clinicId,
    String stayId,
    String kind,
    String label,
    String instructions,
    List<DateTime> times,
    int escalationMinutes,
    String operationId,
  ) async {
    await client.rpc(
      'hospital_prescribe',
      params: {
        'p_clinic_id': clinicId,
        'p_stay_id': stayId,
        'p_kind': kind,
        'p_label': label,
        'p_instructions': instructions,
        'p_times': times.map((t) => t.toUtc().toIso8601String()).toList(),
        'p_escalation_minutes': escalationMinutes,
        'p_operation_id': operationId,
      },
    );
  }

  @override
  Future<void> scheduleReview(
    String clinic,
    String stay,
    String procedure,
    String label,
    String instructions,
    List<DateTime> times,
    int delay,
    String operation,
  ) async {
    await client.rpc(
      'hospital_review_schedule',
      params: {
        'p_clinic_id': clinic,
        'p_stay_id': stay,
        'p_procedure_id': procedure,
        'p_label': label,
        'p_instructions': instructions,
        'p_times': times.map((t) => t.toUtc().toIso8601String()).toList(),
        'p_escalation_minutes': delay,
        'p_operation_id': operation,
      },
    );
  }

  Future<void> transition(
    String action,
    String clinicId,
    HospitalTask task, {
    int? minutes,
    String? reason,
  }) async {
    await client.rpc(
      'hospital_task_action',
      params: {
        'p_clinic_id': clinicId,
        'p_task_id': task.id,
        'p_expected_version': task.version,
        'p_action': action,
        'p_minutes': minutes,
        'p_reason': reason,
      },
    );
  }

  @override
  Future<void> perform(String clinicId, HospitalTask task) =>
      transition('perform', clinicId, task);
  @override
  Future<void> snooze(
    String clinicId,
    HospitalTask task,
    int minutes,
    String reason,
  ) => transition('snooze', clinicId, task, minutes: minutes, reason: reason);
  @override
  Future<void> cancel(String clinicId, HospitalTask task, String reason) =>
      transition('cancel', clinicId, task, reason: reason);
  @override
  Future<void> discharge(
    String clinicId,
    HospitalStay stay,
    String reason,
  ) async {
    await client.rpc(
      'hospital_discharge',
      params: {
        'p_clinic_id': clinicId,
        'p_stay_id': stay.id,
        'p_expected_version': stay.version,
        'p_reason': reason,
      },
    );
  }

  @override
  Future<void> moveCage(
    String clinic,
    HospitalStay stay,
    String cage,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'hospital_cage_set',
      params: {
        'p_clinic_id': clinic,
        'p_stay_id': stay.id,
        'p_version': stay.version,
        'p_cage': cage,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> cageHistory(
    String clinic,
    String stay,
  ) async =>
      (await client.rpc(
                'hospital_cage_history',
                params: {'p_clinic_id': clinic, 'p_stay_id': stay},
              )
              as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
}

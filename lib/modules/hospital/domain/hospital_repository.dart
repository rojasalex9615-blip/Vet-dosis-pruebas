import 'hospital_isolation.dart';
import 'hospital_models.dart';

abstract interface class HospitalRepository {
  Future<HospitalSnapshot> load(String clinicId);
  Future<void> admit(
    String clinicId,
    String patientId,
    String cage,
    String operationId,
  );
  Future<void> prescribe(
    String clinicId,
    String stayId,
    String kind,
    String label,
    String instructions,
    List<DateTime> times,
    int escalationMinutes,
    String operationId,
  );
  Future<void> perform(String clinicId, HospitalTask task);
  Future<void> snooze(
    String clinicId,
    HospitalTask task,
    int minutes,
    String reason,
  );
  Future<void> cancel(String clinicId, HospitalTask task, String reason);
  Future<void> discharge(String clinicId, HospitalStay stay, String reason);
}

abstract interface class HospitalLocationRepository {
  Future<void> moveCage(
    String clinic,
    HospitalStay stay,
    String cage,
    String reason,
    String operation,
  );
  Future<List<Map<String, dynamic>>> cageHistory(String clinic, String stay);
}

abstract interface class HospitalReviewRepository {
  Future<void> scheduleReview(
    String clinic,
    String stay,
    String procedure,
    String label,
    String instructions,
    List<DateTime> times,
    int delay,
    String operation,
  );
}

abstract interface class HospitalResolutionRepository {
  Future<void> followup(
    String clinic,
    HospitalTask task,
    String action,
    int? minutes,
    String reason,
    String operation,
  );
  Future<HospitalDischargePreview> dischargePreview(
    String clinic,
    HospitalStay stay,
  );
  Future<void> confirmDischarge(
    String clinic,
    HospitalStay stay,
    HospitalDischargePreview preview,
    String reason,
    String operation,
  );
}

abstract interface class HospitalIsolationRepository {
  Future<void> setIsolation(
    String clinic,
    HospitalStay stay,
    bool active,
    String reason,
    String reference,
    List<String> steps,
    String operation,
  );
  Future<void> enterIsolation(
    String clinic,
    HospitalStay stay,
    String note,
    String operation,
  );
  Future<void> cleanIsolation(
    String clinic,
    HospitalIsolationArea area,
    List<String> checks,
    String notes,
    String operation,
  );
  Future<List<Map<String, dynamic>>> isolationHistory(
    String clinic,
    String? stay,
  );
}

abstract interface class HospitalCareResultRepository {
  Future<Map<String, dynamic>> careWorkspace(String clinic, String? task);
  Future<void> recordCare(
    String clinic,
    String task,
    int version,
    Map<String, dynamic> data,
    String operation,
  );
}

abstract interface class HospitalAutomationRepository {
  Future<Map<String, dynamic>> automationWorkspace(String clinic, String? stay);
  Future<void> createDailyOrder(
    String clinic,
    String stay,
    Map<String, dynamic> data,
    String operation,
  );
  Future<void> stopDailyOrder(
    String clinic,
    String order,
    String reason,
    String operation,
  );
  Future<void> setNoticeRoute(
    String clinic,
    String primary,
    String mvz,
    String operation,
  );
  Future<void> acknowledgeNotice(
    String clinic,
    String notice,
    String note,
    String operation,
  );
}

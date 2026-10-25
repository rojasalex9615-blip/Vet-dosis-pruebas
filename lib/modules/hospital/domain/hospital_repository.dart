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
  /// Changes the isolation flag using the stay's expected version.
  ///
  /// [reference] and [steps] identify the clinic's protocol snapshot and must
  /// match it on later changes. Removing isolation does not confirm cleaning.
  /// Reuse [operation] for an identical retry; server errors propagate.
  Future<void> setIsolation(
    String clinic,
    HospitalStay stay,
    bool active,
    String reason,
    String reference,
    List<String> steps,
    String operation,
  );
  /// Records the current user's declared access using the stay's version.
  ///
  /// Reuse [operation] for an identical retry; server errors propagate.
  Future<void> enterIsolation(
    String clinic,
    HospitalStay stay,
    String note,
    String operation,
  );
  /// Confirms cleaning of a released area using its complete ordered checklist.
  ///
  /// [notes] may be empty. Reuse [operation] for an identical retry; server
  /// errors propagate.
  Future<void> cleanIsolation(
    String clinic,
    HospitalIsolationArea area,
    List<String> checks,
    String notes,
    String operation,
  );
  /// Reads isolation and cleaning events in chronological order.
  ///
  /// A null [stay] includes the whole clinic. Server errors propagate.
  Future<List<Map<String, dynamic>>> isolationHistory(
    String clinic,
    String? stay,
  );
}

abstract interface class HospitalCareResultRepository {
  /// Loads care results and action permissions, or clinic history for null [task].
  Future<Map<String, dynamic>> careWorkspace(String clinic, String? task);
  /// Appends a result or correction using the expected task [version].
  ///
  /// A pending task is confirmed in the same server transaction. Reuse
  /// [operation] for an identical retry; server errors propagate.
  Future<void> recordCare(
    String clinic,
    String task,
    int version,
    Map<String, dynamic> data,
    String operation,
  );
}

abstract interface class HospitalAutomationRepository {
  /// Loads orders, notices, runtime status, and actions for a stay or clinic.
  ///
  /// A null [stay] selects the clinic overview. Server errors propagate.
  Future<Map<String, dynamic>> automationWorkspace(String clinic, String? stay);
  /// Creates a confirmed daily order, optionally replacing a previous order.
  ///
  /// Reuse [operation] for an identical retry; server errors propagate.
  Future<void> createDailyOrder(
    String clinic,
    String stay,
    Map<String, dynamic> data,
    String operation,
  );
  /// Stops generation and cancels only this order's future pending tasks.
  ///
  /// Reuse [operation] for an identical retry; server errors propagate.
  Future<void> stopDailyOrder(
    String clinic,
    String order,
    String reason,
    String operation,
  );
  /// Sets distinct primary and responsible veterinarian recipient user IDs.
  ///
  /// Eligibility is checked by the server. Reuse [operation] for an identical
  /// retry; server errors propagate.
  Future<void> setNoticeRoute(
    String clinic,
    String primary,
    String mvz,
    String operation,
  );
  /// Records the recipient's response without completing the associated task.
  ///
  /// Reuse [operation] for an identical retry; server errors propagate.
  Future<void> acknowledgeNotice(
    String clinic,
    String notice,
    String note,
    String operation,
  );
}

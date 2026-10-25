abstract class OperationsRepository {
  Future<Map<String, dynamic>> dashboard(String clinic);
  Future<void> write(
    String clinic,
    String action,
    Map<String, dynamic> data,
    String operation,
  );
  Future<List<Map<String, dynamic>>> medical(
    String clinic, {
    Map<String, dynamic>? details,
    bool consent = false,
  });
}

abstract interface class AppointmentPatientRepository {
  Future<List<Map<String, dynamic>>> searchPatients(
    String clinic,
    String query,
  );
}

abstract interface class ServiceCommissionRepository {
  Future<Map<String, dynamic>> commissionAccount(String clinic, {int offset = 0});
  Future<void> settleCommission(
    String clinic,
    String serviceAct,
    String method,
    String reference,
    String operation,
  );
}

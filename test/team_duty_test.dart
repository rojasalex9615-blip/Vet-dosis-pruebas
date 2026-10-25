import 'hospital_test.dart'
    show FakeAlarms, FakeHospital, alerts, task, noon, member;
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/auth_repository.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/auth/presentation/team_duty_screen.dart';
import 'support/fake_auth.dart' show FakeAuth;

const staff = ClinicMembership(
  clinicId: 'a',
  clinicName: 'Synthetic',
  userId: 'user-a',
  role: ClinicRole.auxiliar,
);

class DutyFake extends FakeAuth implements TeamDutyRepository {
  bool admin = false, wrongScope = false, fail = false;
  @override
  Future<Map<String, dynamic>> dutyWorkspace(String clinic) async {
    if (fail) throw StateError('offline');
    return {
      'version': 1,
      'clinic_id': wrongScope ? 'b' : clinic,
      'actor_id': 'user-a',
      'admin': admin,
      'members': [
        {'id': 'user-a', 'name': 'Synthetic staff', 'on_duty': true},
      ],
      'entries': [],
    };
  }

  @override
  Future<void> saveDuty(
    String clinic,
    String user,
    Map<String, dynamic> data,
    String operation,
  ) async {}
  @override
  Future<void> cancelDuty(
    String clinic,
    String entry,
    String reason,
    String operation,
  ) async {}
}

void main() {
  test(
    'Editing retains local dates and selected cover without reusing the old reason',
    () {
      final initial = dutyEntryInitial({
        'id': 'old',
        'cover_id': 'cover',
        'zone': 'America/Mexico_City',
        'starts_at': '2026-10-25T04:00:00Z',
        'ends_at': '2026-10-25T12:00:00Z',
        'reason': 'old private reason',
      });
      expect(initial['start_day'], '2026-10-24');
      expect(initial['start_time'], '22:00');
      expect(initial['end_day'], '2026-10-25');
      expect(initial['end_time'], '06:00');
      expect(initial['cover_id'], 'cover');
      expect(initial.containsKey('reason'), false);
    },
  );
  test(
    'Duty routing cancels previously scheduled alarms and lost capability fails closed',
    () async {
      final backend = FakeAlarms();
      final alarm = await alerts(backend);
      await alarm.enable();
      final repo = FakeHospital()
        ..snapshot = HospitalSnapshot([], [
          task(due: noon.add(const Duration(hours: 1))),
        ]);
      final model = HospitalViewModel(repo, member(ClinicRole.mvz), alarm);
      await model.refresh();
      expect(backend.scheduled, isNotEmpty);
      repo.snapshot = HospitalSnapshot(
        [],
        repo.snapshot.tasks,
        dutyRouting: true,
      );
      await model.refresh();
      expect(backend.scheduled, isEmpty);
      expect(backend.cancelled, isNotEmpty);
      repo.snapshot = HospitalSnapshot([], repo.snapshot.tasks);
      await model.refresh();
      expect(model.error, isNotNull);
      expect(backend.scheduled, isEmpty);
      model.dispose();
      alarm.dispose();
    },
  );
  test(
    'Dates and times reject normalization, preserve overnight and explicit zone',
    () {
      final data = {
        'kind': 'shift',
        'user_id': 'user-a',
        'start_day': '2026-10-24',
        'start_time': '22:30',
        'end_day': '2026-10-25',
        'end_time': '07:15',
        'zone': 'America/Mexico_City',
        'reason': 'Synthetic',
      };
      final value = dutyFormData(data);
      expect(value['start_minute'], 1350);
      expect(value['end_minute'], 435);
      expect(value['zone'], 'America/Mexico_City');
      expect(value.containsKey('user_id'), false);
      expect(
        () => dutyFormData({...data, 'start_day': '2026-02-30'}),
        throwsFormatException,
      );
      expect(
        () => dutyFormData({...data, 'end_time': '24:00'}),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'Staff can add own shift; absence admin action stays hidden and failed reload clears state',
    (tester) async {
      final repo = DutyFake()..rows = [staff];
      final model = AuthViewModel(repo);
      await model.start();
      await tester.pumpWidget(
        MaterialApp(
          home: TeamDutyScreen(model: model, clinic: staff),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agregar turno'), findsOneWidget);
      expect(find.text('Autorizar falta y elegir cobertura'), findsNothing);
      expect(find.text('Synthetic staff'), findsOneWidget);
      repo.fail = true;
      await tester.tap(find.text('Actualizar horarios'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic staff'), findsNothing);
      expect(find.text('Agregar turno'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      await repo.controller.close();
    },
  );
  testWidgets('Admin sees absence and cover; mismatched clinic fails closed', (
    tester,
  ) async {
    final repo = DutyFake()
      ..rows = [staff]
      ..admin = true;
    final model = AuthViewModel(repo);
    await model.start();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamDutyScreen(model: model, clinic: staff),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Autorizar falta y elegir cobertura'), findsOneWidget);
    repo.wrongScope = true;
    await tester.tap(find.text('Actualizar horarios'));
    await tester.pumpAndSettle();
    expect(find.text('Autorizar falta y elegir cobertura'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    await repo.controller.close();
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_isolation.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/data/supabase_hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_screen.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_isolation_actions.dart';
import 'hospital_test.dart'
    show FakeHospital, FakeAlarms, alerts, stay, member, noon, task;
import 'patients_test.dart' show FakePatients;

HospitalIsolation flag() => HospitalIsolation(
  stayId: 'stay-a',
  active: true,
  reference: 'Protocolo ficticio v1 p1',
  steps: const ['Paso ficticio A', 'Paso ficticio B'],
  reason: 'Motivo ficticio',
  changedBy: 'person-a',
  changedAt: noon,
);
HospitalIsolationArea area({bool ready = true}) => HospitalIsolationArea(
  id: 'area',
  stayId: 'stay-a',
  cage: 'Box 1',
  patientName: 'Paciente ficticio',
  reference: 'Protocolo ficticio v1 p1',
  steps: flag().steps,
  exposedAt: noon,
  releasedAt: ready ? noon : null,
);

class IsolationRepo extends FakeHospital
    implements HospitalIsolationRepository {
  final operations = <String>[];
  List<String>? checks;
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
    writes++;
    operations.add(operation);
  }

  @override
  Future<void> enterIsolation(
    String clinic,
    HospitalStay stay,
    String note,
    String operation,
  ) async {
    writes++;
    operations.add(operation);
  }

  @override
  Future<void> cleanIsolation(
    String clinic,
    HospitalIsolationArea area,
    List<String> checks,
    String notes,
    String operation,
  ) async {
    writes++;
    operations.add(operation);
    this.checks = checks;
  }

  @override
  Future<List<Map<String, dynamic>>> isolationHistory(
    String clinic,
    String? stay,
  ) async => [];
}

HospitalSnapshot snapshot({
  bool manage = false,
  bool handle = false,
  bool enabled = true,
  List<HospitalTask> tasks = const [],
}) => HospitalSnapshot(
  [stay()],
  tasks,
  isolationEnabled: enabled,
  isolations: enabled ? [flag()] : [],
  isolationAreas: enabled ? [area()] : [],
  permissions: {
    'hospital.isolation.manage': manage,
    'hospital.isolation.handle': handle,
  },
);
Future<void> tap(WidgetTester t, String label) async {
  final f = find.text(label);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  test(
    'snapshot records retain source, area identity, authorship and clinic scope',
    () {
      final row = <String, dynamic>{
        'clinic_id': 'a',
        'stay_id': 'stay-a',
        'active': true,
        'protocol_reference': 'Protocolo ficticio v1 p1',
        'steps': ['Paso ficticio A', 'Paso ficticio B'],
        'reason': 'Motivo ficticio',
        'changed_by': 'person-a',
        'changed_at': '2026-10-24T10:00:00+00:00',
      };
      final isolation = HospitalIsolation.read(row, 'a');
      expect(isolation.changedBy, 'person-a');
      expect(isolation.steps, flag().steps);
      expect(() => HospitalIsolation.read(row, 'other'), throwsFormatException);
      final rawArea = <String, dynamic>{
        ...row,
        'id': 'area',
        'cage': null,
        'patient_name': 'Paciente ficticio',
        'exposed_at': '2026-10-24T10:00:00+00:00',
        'released_at': '2026-10-24T11:00:00+00:00',
      };
      final released = HospitalIsolationArea.read(rawArea, 'a');
      expect(released.ready, true);
      expect(released.cageLabel, 'Área sin jaula asignada');
      expect(
        () => HospitalIsolationArea.read({
          ...rawArea,
          'cleaned_at': '2026-10-24T12:00:00Z',
        }, 'a'),
        throwsFormatException,
      );
    },
  );

  test('new isolation actions never use legacy admin fallback', () async {
    final r = IsolationRepo(), a = await alerts(FakeAlarms(supported: false));
    final m = HospitalViewModel(r, member(ClinicRole.admin), a);
    addTearDown(m.dispose);
    addTearDown(a.dispose);
    await m.refresh();
    await expectLater(
      HospitalIsolationActions(m, () => true).save(() async {
        r.writes++;
      }, 'hospital.isolation.manage'),
      throwsFormatException,
    );
    expect(r.writes, 0);
  });

  test(
    'checklist requires nonempty distinct explicit steps; no clinical defaults',
    () {
      for (final steps in [
        <String>[],
        [''],
        [' A ', 'A'],
        List.generate(31, (i) => '$i'),
      ]) {
        expect(() => isolationSteps(steps), throwsFormatException);
      }
      expect(isolationSteps([' A ', 'B']), ['A', 'B']);
    },
  );
  test(
    'capability/permissions do not fall back to admin on contract loss',
    () async {
      final r = IsolationRepo()..snapshot = snapshot(),
          a = await alerts(FakeAlarms(supported: false));
      final m = HospitalViewModel(r, member(ClinicRole.admin), a);
      addTearDown(m.dispose);
      addTearDown(a.dispose);
      await m.refresh();
      expect(m.isolationPermission('hospital.isolation.manage'), false);
      r.snapshot = snapshot(manage: true);
      await m.refresh();
      expect(m.isolationPermission('hospital.isolation.manage'), true);
      r.snapshot = snapshot(manage: true, enabled: false);
      await m.refresh();
      expect(m.error, isNotNull);
      expect(m.snapshot.stays, isEmpty);
      expect(m.isolationPermission('hospital.isolation.manage'), false);
    },
  );
  test(
    'context revocation prevents isolation writes even with earlier grant',
    () async {
      final r = IsolationRepo()..snapshot = snapshot(manage: true),
          a = await alerts(FakeAlarms(supported: false));
      final m = HospitalViewModel(r, member(ClinicRole.mvz), a);
      addTearDown(m.dispose);
      addTearDown(a.dispose);
      await m.refresh();
      final actions = HospitalIsolationActions(m, () => false);
      await expectLater(
        actions.save(
          () => r.enterIsolation('a', stay(), 'x', 'operation'),
          'hospital.isolation.manage',
        ),
        throwsFormatException,
      );
      expect(r.writes, 0);
    },
  );
  test(
    'RPC cleaning requires released area and all snapshot steps; no parallel medication write',
    () async {
      final requests = <String>[], bodies = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.test',
        'synthetic',
        httpClient: MockClient((r) async {
          requests.add(r.url.path);
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(
            '"area"',
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      addTearDown(client.dispose);
      final r = SupabaseHospitalRepository(client);
      await expectLater(
        r.cleanIsolation(
          'a',
          area(ready: false),
          flag().steps,
          '',
          'operation',
        ),
        throwsFormatException,
      );
      await expectLater(
        r.cleanIsolation('a', area(), ['Paso ficticio A'], '', 'operation'),
        throwsFormatException,
      );
      expect(requests, isEmpty);
      await r.cleanIsolation('a', area(), flag().steps, 'Hecho', 'operation');
      expect(requests.single, endsWith('/hospital_isolation_clean'));
      expect(bodies.single['p_checks'], flag().steps);
      expect(bodies.single['p_operation'], 'operation');
    },
  );
  test(
    'unknown isolation contract fails before returning partial hospital data',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'synthetic',
        httpClient: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'capabilities': {'isolation_version': 2},
              'stays': [],
              'tasks': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseHospitalRepository(client).load('a'),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    '320dp hospital displays isolation and cleaning across discharge; read-only hides actions',
    (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final r = IsolationRepo()
            ..snapshot = snapshot(tasks: [task(due: DateTime.now())]),
          a = await alerts(FakeAlarms(supported: false));
      addTearDown(a.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HospitalScreen(
                repository: r,
                patients: FakePatients(),
                member: member(ClinicRole.auxiliar),
                alerts: a,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('DESINFECCIÓN PENDIENTE'), findsOneWidget);
      expect(find.textContaining('AISLAMIENTO ·'), findsOneWidget);
      expect(find.text('Registrar acceso a aislamiento'), findsNothing);
      expect(find.text('Revisar retiro de aislamiento'), findsNothing);
      await tap(t, 'Paciente × hora');
      expect(find.textContaining('\nAISLAMIENTO'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'every cleaning step requires own explicit check before writing',
    (t) async {
      final r = IsolationRepo()..snapshot = snapshot(handle: true),
          a = await alerts(FakeAlarms(supported: false));
      final m = HospitalViewModel(r, member(ClinicRole.auxiliar), a);
      addTearDown(m.dispose);
      addTearDown(a.dispose);
      await m.refresh();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HospitalIsolationActions(
                  m,
                  () => true,
                ).clean(context, area()),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Abrir');
      await tap(t, 'Guardar');
      expect(r.writes, 0);
      await tap(t, 'Paso ficticio A');
      await tap(t, 'Confirmo que realicé todos los pasos y revisé el área');
      await tap(t, 'Guardar');
      expect(r.writes, 0);
      await tap(t, 'Paso ficticio B');
      await tap(t, 'Guardar');
      expect(r.writes, 1);
      expect(r.checks, flag().steps);
      expect(t.takeException(), isNull);
    },
  );
}

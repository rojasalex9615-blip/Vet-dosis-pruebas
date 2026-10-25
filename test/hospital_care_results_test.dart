import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_care_result.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/data/supabase_hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_care_results_screen.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'package:vetdosis_pro/modules/prescribing/presentation/rx_entry_screen.dart';
import 'hospital_test.dart' show FakeHospital, FakeAlarms, alerts;
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';

const member = ClinicMembership(
  clinicId: 'a',
  clinicName: 'Synthetic',
  userId: 'user-a',
  role: ClinicRole.admin,
);

Map<String, dynamic> data() => {
  'care_kind': 'feeding',
  'offered': '2.123456789',
  'consumed': '0',
  'unit': 'porción',
  'findings': 'Captura sintética',
  'observed_at': '2026-10-24T12:00:00Z',
  'confirmed': true,
};
Map<String, dynamic> row({String id = 'original', String? replaces}) => {
  ...data(),
  'id': id,
  'clinic_id': member.clinicId,
  'task_id': 'task',
  'patient_id': 'patient',
  'patient_name': 'Paciente sintético',
  'task_label': 'Cuidado sintético',
  'actor_id': member.userId,
  'created_at': '2026-10-24T13:00:00+00:00',
  'replaces_id': replaces,
  'correction_reason': replaces == null ? null : 'Corrección sintética',
};
Map<String, dynamic> workspace({bool history = false}) => {
  'schema_version': 1,
  'clinic_id': member.clinicId,
  'actor_id': member.userId,
  'task_id': history ? null : 'task',
  'task': history
      ? null
      : {
          'id': 'task',
          'clinic_id': member.clinicId,
          'version': 7,
          'patient_id': 'patient',
          'patient_name': 'Paciente sintético',
          'label': 'Cuidado sintético',
          'instructions': 'Indicación sintética',
          'state': 'pending',
        },
  'actions': {'record': !history, 'correct': false},
  'records': <Map<String, dynamic>>[],
};

class ResultFake implements HospitalCareResultRepository {
  Map<String, dynamic> value = workspace();
  Completer<Map<String, dynamic>>? pending;
  final writes = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> careWorkspace(
    String clinic,
    String? task,
  ) async => pending == null ? value : pending!.future;
  @override
  Future<void> recordCare(
    String clinic,
    String task,
    int version,
    Map<String, dynamic> data,
    String operation,
  ) async {
    writes.add({
      'clinic': clinic,
      'task': task,
      'version': version,
      'data': data,
      'operation': operation,
    });
    // Model a response lost after server commit. Retry must still use the captured version/key.
    value = {
      ...workspace(),
      'actions': {'record': false, 'correct': true},
      'task': {...workspace()['task'], 'version': 8},
      'records': [row()],
    };
    if (fail) throw StateError('response_lost');
  }
}

void main() {
  test(
    'exact consumption includes zero and requires explicit facts without targets',
    () {
      expect(validateCareResult(data())['offered'], '2.123456789');
      expect(validateCareResult(data())['consumed'], '0');
      for (final invalid in [
        {...data()}..remove('offered'),
        {...data(), 'offered': '0'},
        {...data(), 'consumed': '-1'},
        {...data(), 'consumed': '3'},
        {...data(), 'offered': '1e3'},
        {...data(), 'unit': 'kg'},
        {...data(), 'confirmed': false},
        {...data(), 'findings': ''},
        {...data(), 'observed_at': '2026-02-30T12:00:00Z'},
        {...data(), 'observed_at': '2026-10-24T12:00:00'},
        {...data(), 'replaces_id': 'original'},
        {...data(), 'care_kind': 'catheter_review'},
      ]) {
        expect(() => validateCareResult(invalid), throwsFormatException);
      }
      for (final kind in ['catheter_review', 'equipment_change', 'other']) {
        final device = {...data(), 'care_kind': kind}
          ..remove('offered')
          ..remove('consumed')
          ..remove('unit');
        expect(validateCareResult(device).containsKey('consumed'), false);
      }
    },
  );
  test(
    'workspace rejects actor, clinic, task, patient, version and partial contracts',
    () {
      for (final mismatch in [
        {'schema_version': 2},
        {'actor_id': 'other'},
        {'clinic_id': 'foreign'},
        {'task_id': 'other'},
        {
          'actions': {'record': true},
        },
        {
          'task': {...workspace()['task'], 'version': 0},
        },
        {
          'records': [
            {...row(), 'task_id': 'other'},
          ],
        },
        {
          'records': [
            {...row(), 'patient_id': 'other'},
          ],
        },
        {
          'records': [
            {...row(), 'clinic_id': 'foreign'},
          ],
        },
        {
          'records': [
            {...row(), 'consumed': '3'},
          ],
        },
      ]) {
        expect(
          () => HospitalCareWorkspace.read(
            {...workspace(), ...mismatch},
            member.clinicId,
            member.userId,
            'task',
          ),
          throwsFormatException,
        );
      }
      final w = HospitalCareWorkspace.read(
        {
          ...workspace(),
          'records': [row(), row(id: 'correction', replaces: 'original')],
        },
        member.clinicId,
        member.userId,
        'task',
      );
      expect(w.records.length, 2);
      expect(w.replaced('original'), true);
      expect(
        () => HospitalCareWorkspace.read(
          {
            ...workspace(history: true),
            'actions': {'record': true, 'correct': false},
          },
          member.clinicId,
          member.userId,
          null,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'RPC preserves captured version and operation; unknown capability fails closed',
    () async {
      final requests = <Map<String, dynamic>>[];
      var version = 1;
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic',
        httpClient: MockClient((request) async {
          requests.add({
            'path': request.url.path,
            'body': jsonDecode(request.body),
          });
          final Object result = request.url.path.endsWith('hospital_snapshot')
              ? {
                  'stays': [],
                  'tasks': [],
                  'capabilities': {'care_results_version': version},
                }
              : request.url.path.endsWith('hospital_care_workspace')
              ? workspace()
              : 'result';
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabaseHospitalRepository(client);
      expect((await repo.load(member.clinicId)).careResultsEnabled, true);
      version = 2;
      await expectLater(repo.load(member.clinicId), throwsFormatException);
      await repo.careWorkspace(member.clinicId, 'task');
      await repo.recordCare(member.clinicId, 'task', 7, data(), 'operation');
      expect(requests.last['body'], {
        'p_clinic': member.clinicId,
        'p_task': 'task',
        'p_version': 7,
        'p_data': validateCareResult(data()),
        'p_operation': 'operation',
      });
      expect(requests[2]['body'], {
        'p_clinic': member.clinicId,
        'p_task': 'task',
      });
    },
  );
  test(
    'previously advertised capability disappearing clears snapshot',
    () async {
      final repo = FakeHospital()
        ..snapshot = const HospitalSnapshot([], [], careResultsEnabled: true);
      final model = HospitalViewModel(repo, member, await alerts(FakeAlarms()));
      addTearDown(model.dispose);
      await model.refresh();
      expect(model.snapshot.careResultsEnabled, true);
      repo.snapshot = const HospitalSnapshot([], []);
      await model.refresh();
      expect(model.snapshot.careResultsEnabled, false);
      expect(model.error, isNotNull);
    },
  );
  testWidgets(
    '320dp entry is explicit and lost response retries keep version and identity',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ResultFake()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalCareResultsScreen(
            repository: repo,
            member: member,
            taskId: 'task',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar resultado de mi cuidado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alimentación'));
      await tester.pumpAndSettle();
      Future<void> reveal(Finder f) async {
        final scrollable = find.byType(Scrollable).first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(f, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      Future<void> text(String label, String value) async {
        final f = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.labelText ?? '').startsWith(label),
        );
        await reveal(f);
        await tester.enterText(f, value);
        await tester.pump();
      }

      final date = find.text('Fecha y hora reales del cuidado *');
      await reveal(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await text('Cantidad realmente ofrecida', '2.123456789');
      await text('Cantidad realmente consumida', '0');
      final unit = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Unidad de ambas cantidades *',
      );
      await reveal(unit);
      await tester.tap(unit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('porción').last);
      await tester.pumpAndSettle();
      await text('Hallazgos', 'Captura sintética');
      Future<void> save() async {
        final f = find.widgetWithText(FilledButton, 'Guardar');
        await reveal(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await save();
      expect(repo.writes, isEmpty);
      final checkbox = find.byType(CheckboxListTile);
      await reveal(checkbox);
      expect(tester.widget<CheckboxListTile>(checkbox).value, false);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await save();
      await save();
      expect(repo.writes.length, 2);
      expect(repo.writes.map((w) => w['operation']).toSet().length, 1);
      expect(repo.writes.map((w) => w['version']).toSet(), {7});
      expect(repo.writes.first['data']['consumed'], '0');
      await text('Hallazgos', 'Captura revisada');
      await save();
      expect(repo.writes.map((w) => w['operation']).toSet().length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('history preserves corrections and offers no write actions', (
    tester,
  ) async {
    final repo = ResultFake()
      ..value = {
        ...workspace(history: true),
        'records': [row(), row(id: 'correction', replaces: 'original')],
      };
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalCareResultsScreen(repository: repo, member: member),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registrar resultado de mi cuidado'), findsNothing);
    expect(find.text('Corregir conservando original'), findsNothing);
    expect(
      find.text('Sustituido por corrección · antecedente conservado'),
      findsOneWidget,
    );
  });
  testWidgets('correction appends a reason and refuses a superseded result', (
    tester,
  ) async {
    final repo = ResultFake()
      ..value = {
        ...workspace(),
        'actions': {'record': false, 'correct': true},
        'records': [row()],
      };
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalCareResultsScreen(
          repository: repo,
          member: member,
          taskId: 'task',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final correct = find.text('Corregir conservando original');
    await tester.ensureVisible(correct);
    await tester.tap(correct);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambio de equipo'));
    await tester.pumpAndSettle();
    final form = tester.widget<RxEntryScreen>(find.byType(RxEntryScreen));
    expect(form.initial, isEmpty);
    expect(
      form.fields.any((f) => f.key == 'correction_reason' && f.required),
      true,
    );
    final device =
        {
            ...data(),
            'care_kind': 'equipment_change',
            'correction_reason': 'Rectificación sintética',
          }
          ..remove('offered')
          ..remove('consumed')
          ..remove('unit');
    await form.submit(device, 'correction-operation');
    expect(repo.writes.single['data']['replaces_id'], 'original');
    expect(
      repo.writes.single['data']['correction_reason'],
      'Rectificación sintética',
    );
    await tester.pumpWidget(const SizedBox());
    repo.value = {
      ...workspace(),
      'actions': {'record': false, 'correct': true},
      'records': [row(), row(id: 'new', replaces: 'original')],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalCareResultsScreen(
          repository: repo,
          member: member,
          taskId: 'task',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Sustituido por corrección · antecedente conservado'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Corregir conservando original'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Corregir conservando original'), findsOneWidget);
  });
  testWidgets('late disposed load and failed refresh expose no stale actions', (
    tester,
  ) async {
    final repo = ResultFake()..pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalCareResultsScreen(
          repository: repo,
          member: member,
          taskId: 'task',
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    repo.pending!.complete(workspace());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    repo.pending = null;
    await tester.pumpWidget(
      MaterialApp(
        home: HospitalCareResultsScreen(
          repository: repo,
          member: member,
          taskId: 'task',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registrar resultado de mi cuidado'), findsOneWidget);
    repo.value = {...workspace(), 'actor_id': 'other'};
    await tester.tap(find.text('Actualizar resultados'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar resultado de mi cuidado'), findsNothing);
    expect(find.textContaining('No se pudieron consultar'), findsOneWidget);
  });
}

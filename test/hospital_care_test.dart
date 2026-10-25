import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/hospital/data/supabase_hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_care.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_repository.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_care_form.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_screen.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_view_model.dart';
import 'hospital_test.dart' show FakeAlarms, FakeHospital, alerts, member, stay;
import 'patients_test.dart' show FakePatients;

final clock = DateTime(2026, 10, 24, 8);
final tomorrow = DateTime(2026, 10, 25);
const procedures = [HospitalReviewType('care-type', 'Cuidados ficticios')];
HospitalCareDraft diet({String portion = '12,125', String unit = 'g'}) =>
    HospitalCareDraft(
      kind: HospitalCareKind.feeding,
      food: 'Alimento ficticio',
      portion: portion,
      unit: unit,
      instructions: 'Indicación sintética; no usar en pacientes.',
    );
List<DateTime> schedule({List<int> minutes = const [10 * 60], DateTime? end}) =>
    dailyCareSchedule(
      firstDay: tomorrow,
      lastDay: end ?? tomorrow,
      minutesOfDay: minutes,
      now: clock,
    );

class CareHospital extends FakeHospital implements HospitalReviewRepository {
  CareHospital() {
    snapshot = HospitalSnapshot(
      [stay()],
      [],
      typedReviews: true,
      reviewTypes: procedures,
      permissions: const {'hospital.schedule': true},
    );
  }
  Map<String, dynamic>? order;
  @override
  Future<void> scheduleReview(
    String clinic,
    String stayId,
    String procedure,
    String label,
    String instructions,
    List<DateTime> times,
    int delay,
    String operation,
  ) async {
    writes++;
    order = {
      'clinic': clinic,
      'stay': stayId,
      'procedure': procedure,
      'label': label,
      'instructions': instructions,
      'times': times,
      'delay': delay,
      'operation': operation,
    };
  }
}

Future<void> selectDates(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Elegir fechas'));
  await tester.tap(find.text('Elegir fechas'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(DateRangePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), '10/25/2026');
  await tester.enterText(fields.at(1), '10/26/2026');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(find.byType(DateRangePickerDialog), findsNothing);
}

Future<void> addDailyTime(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Añadir horario diario'));
  await tester.tap(find.text('Añadir horario diario'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), '10');
  await tester.enterText(fields.at(1), '15');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  test(
    'Feeding preserves entered precision, units and instructions without defaults',
    () {
      final draft = diet();
      expect(draft.details, contains('12,125 g'));
      expect(draft.details, contains('Indicación sintética'));
      expect(draft.label, 'Alimentación · Alimento ficticio');
      for (final portion in ['', '0', '-1', 'NaN', '1e3']) {
        expect(() => diet(portion: portion), throwsFormatException);
      }
      expect(() => diet(unit: ''), throwsFormatException);
      expect(() => diet(unit: 'mg/kg'), throwsFormatException);
      expect(
        () => HospitalCareDraft(
          kind: HospitalCareKind.feeding,
          food: '',
          portion: '1',
          unit: 'g',
          instructions: 'Synthetic',
        ),
        throwsFormatException,
      );
    },
  );
  test('Device orders require an entered device and instructions', () {
    for (final kind in [
      HospitalCareKind.catheterReview,
      HospitalCareKind.equipmentChange,
    ]) {
      expect(
        () => HospitalCareDraft(kind: kind, instructions: 'Synthetic'),
        throwsFormatException,
      );
      expect(
        () => HospitalCareDraft(
          kind: kind,
          device: 'Synthetic',
          instructions: '',
        ),
        throwsFormatException,
      );
      final draft = HospitalCareDraft(
        kind: kind,
        device: 'Sitio ficticio',
        instructions: 'Cuidado capturado',
      );
      expect(draft.label, startsWith(kind.title));
      expect(draft.details, contains('Sitio ficticio'));
    }
  });
  test(
    'Daily schedule expands inclusive dates, sorted UTC instants and exact minutes',
    () {
      final times = schedule(
        minutes: [17 * 60 + 45, 9 * 60 + 5],
        end: DateTime(2026, 10, 27),
      );
      expect(times, hasLength(6));
      expect(times.every((t) => t.isUtc), true);
      expect(times.first.toLocal(), DateTime(2026, 10, 25, 9, 5));
      expect(times.last.toLocal(), DateTime(2026, 10, 27, 17, 45));
      expect(() => times.add(clock), throwsUnsupportedError);
    },
  );
  test(
    'Daily schedule rejects duplicates, invalid days, excessive batches and past times',
    () {
      for (final minutes in [
        <int>[],
        [600, 600],
        [-1],
        [1440],
      ]) {
        expect(() => schedule(minutes: minutes), throwsFormatException);
      }
      expect(
        () => schedule(end: DateTime(2026, 10, 24)),
        throwsFormatException,
      );
      expect(
        () => schedule(end: DateTime(2026, 11, 25)),
        throwsFormatException,
      );
      expect(
        () => schedule(
          minutes: List.generate(7, (i) => i * 60),
          end: DateTime(2026, 11, 24),
        ),
        throwsFormatException,
      );
      expect(
        () => dailyCareSchedule(
          firstDay: clock,
          lastDay: clock,
          minutesOfDay: [8 * 60],
          now: clock,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Daily wall-clock schedule handles DST and rejects a nonexistent local time',
    () {
      expect(
        () => dailyCareSchedule(
          firstDay: DateTime(2027, 3, 14),
          lastDay: DateTime(2027, 3, 14),
          minutesOfDay: [150],
          now: clock,
        ),
        throwsFormatException,
      );
      final times = dailyCareSchedule(
        firstDay: DateTime(2026, 10, 31),
        lastDay: DateTime(2026, 11, 2),
        minutesOfDay: [10 * 60],
        now: clock,
      );
      expect(times.map((t) => t.toLocal().hour), everyElement(10));
      expect(times[1].difference(times[0]), const Duration(hours: 25));
    },
    skip: Platform.environment['TZ'] != 'America/New_York',
  );

  test(
    'Care uses typed scheduling only with current permissions, stay and procedure',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = CareHospital();
      final vm = HospitalViewModel(
        repo,
        member(ClinicRole.admin),
        a,
        now: () => clock,
      );
      await vm.refresh();
      expect(vm.canScheduleCare, true);
      expect(
        await vm.scheduleCare(
          stay(),
          'wrong-type',
          diet(),
          schedule(),
          10,
          'op',
        ),
        false,
      );
      expect(repo.writes, 0);
      expect(
        await vm.scheduleCare(
          stay(),
          'care-type',
          diet(),
          schedule(),
          10,
          'op',
        ),
        true,
      );
      expect(repo.order?['clinic'], 'a');
      expect(repo.order?['stay'], 'stay-a');
      expect(repo.order?['instructions'], contains('12,125 g'));
      repo.snapshot = HospitalSnapshot(
        [],
        [],
        typedReviews: true,
        reviewTypes: procedures,
        permissions: const {'hospital.schedule': true},
      );
      await vm.refresh();
      expect(
        await vm.scheduleCare(
          stay(),
          'care-type',
          diet(),
          schedule(),
          10,
          'op',
        ),
        false,
      );
      expect(repo.writes, 1);
      repo.fail = true;
      await vm.refresh();
      expect(vm.canScheduleCare, false);
      expect(
        await vm.scheduleCare(
          stay(),
          'care-type',
          diet(),
          schedule(),
          10,
          'op',
        ),
        false,
      );
      expect(repo.writes, 1);
      vm.dispose();
      a.dispose();
    },
  );
  test(
    'Legacy authority, absent types and revoked scheduling cannot create care orders',
    () async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = CareHospital();
      final vm = HospitalViewModel(
        repo,
        member(ClinicRole.admin),
        a,
        now: () => clock,
      );
      for (final snapshot in [
        HospitalSnapshot([stay()], [], reviewTypes: procedures),
        HospitalSnapshot(
          [stay()],
          [],
          typedReviews: true,
          permissions: const {'hospital.schedule': true},
        ),
        HospitalSnapshot(
          [stay()],
          [],
          typedReviews: true,
          reviewTypes: procedures,
          permissions: const {},
        ),
      ]) {
        repo.snapshot = snapshot;
        await vm.refresh();
        expect(vm.canScheduleCare, false);
        expect(
          await vm.scheduleCare(
            stay(),
            'care-type',
            diet(),
            schedule(),
            10,
            'op',
          ),
          false,
        );
      }
      expect(repo.writes, 0);
      vm.dispose();
      a.dispose();
    },
  );
  test(
    'Repository sends the existing typed RPC with UTC schedule and stable operation id',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '"synthetic-order"',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = SupabaseHospitalRepository(client);
      final draft = diet();
      final times = schedule(end: DateTime(2026, 10, 26));
      await repo.scheduleReview(
        'clinic',
        'stay',
        'type',
        draft.label,
        draft.details,
        times,
        11,
        'stable-operation',
      );
      expect(requests.single.url.path, '/rest/v1/rpc/hospital_review_schedule');
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['p_procedure_id'], 'type');
      expect(body['p_instructions'], contains('12,125 g'));
      expect(
        body['p_times'],
        times.map((t) => t.toUtc().toIso8601String()).toList(),
      );
      expect(body['p_operation_id'], 'stable-operation');
      await client.dispose();
    },
  );

  testWidgets(
    'Feeding form requires explicit fields and review; retries retain identity until content changes',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final operations = <String>[];
      final saved = <List<DateTime>>[];
      final details = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalCareForm(
            stay: stay(),
            kind: HospitalCareKind.feeding,
            reviewTypes: procedures,
            now: () => clock,
            save: (procedure, draft, times, delay, operation) async {
              expect(procedure, 'care-type');
              expect(delay, 11);
              operations.add(operation);
              saved.add(times);
              details.add(draft.details);
              return false;
            },
          ),
        ),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .initialValue,
        isNull,
      );
      expect(
        tester.widget<TextField>(field('Porción por horario')).controller!.text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('Guardar orden de cuidados'));
      await tester.tap(find.text('Guardar orden de cuidados'));
      await tester.pumpAndSettle();
      expect(operations, isEmpty);
      expect(find.textContaining('Revisa paciente'), findsOneWidget);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).first,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuidados ficticios').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Alimento indicado'), 'Alimento ficticio');
      await tester.enterText(field('Porción por horario'), '12,125');
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).last,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('g').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        field('Indicaciones de alimentación'),
        'Indicación ficticia',
      );
      await selectDates(tester);
      await addDailyTime(tester);
      await tester.enterText(field('Aviso de retraso tras (minutos)'), '11');
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.ensureVisible(find.byType(CheckboxListTile));
        if (attempt == 0) await tester.tap(find.byType(CheckboxListTile));
        await tester.ensureVisible(find.text('Guardar orden de cuidados'));
        await tester.tap(find.text('Guardar orden de cuidados'));
        await tester.pumpAndSettle();
      }
      expect(saved.first, hasLength(2));
      expect(saved.first.first.toLocal().minute, 15);
      expect(details.first, contains('12,125 g'));
      expect(operations, hasLength(2));
      expect(operations[0], operations[1]);
      await tester.enterText(field('Porción por horario'), '13');
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('Guardar orden de cuidados'));
      await tester.tap(find.text('Guardar orden de cuidados'));
      await tester.pumpAndSettle();
      expect(operations, hasLength(3));
      expect(operations.last, isNot(operations.first));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Device forms do not prefill clinical values or manufacture procedure types',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: HospitalCareForm(
            stay: stay(),
            kind: HospitalCareKind.catheterReview,
            reviewTypes: const [],
            now: () => clock,
            save: (_, _, _, _, _) async => throw StateError('must not save'),
          ),
        ),
      );
      expect(find.textContaining('No hay tipos activos'), findsOneWidget);
      expect(find.text('Porción por horario'), findsNothing);
      expect(
        tester
            .widget<TextField>(field('Dispositivo / sitio a revisar o cambiar'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('Guardar orden de cuidados'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Care tasks appear in daily sheet with portions, completion identity and permissions',
    (tester) async {
      final a = await alerts(FakeAlarms(supported: false));
      final repo = CareHospital();
      final draft = diet();
      repo.snapshot = HospitalSnapshot(
        [stay()],
        [
          HospitalTask(
            id: 'care',
            stayId: stay().id,
            kind: 'revision',
            label: draft.label,
            instructions: draft.details,
            dueAt: DateTime.now(),
            escalationMinutes: 11,
            state: HospitalTaskState.done,
            version: 2,
            performedBy: 'synthetic-performer',
            performedAt: DateTime.now(),
            actions: const {},
          ),
        ],
        typedReviews: true,
        reviewTypes: procedures,
        permissions: const {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HospitalScreen(
                repository: repo,
                patients: FakePatients(),
                member: member(ClinicRole.admin),
                alerts: a,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Alimentación · Alimento ficticio'),
        findsOneWidget,
      );
      expect(find.textContaining('12,125 g'), findsOneWidget);
      expect(find.textContaining('synthetic-performer'), findsOneWidget);
      expect(find.text('Alimentación y catéter'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
  testWidgets(
    'Care menu exposes all three options on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final a = await alerts(FakeAlarms(supported: false));
      final repo = CareHospital();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HospitalScreen(
                repository: repo,
                patients: FakePatients(),
                member: member(ClinicRole.admin),
                alerts: a,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Alimentación y catéter'));
      await tester.tap(find.text('Alimentación y catéter'));
      await tester.pumpAndSettle();
      for (final kind in HospitalCareKind.values) {
        expect(find.text(kind.title), findsOneWidget);
      }
      await tester.tap(find.text(HospitalCareKind.equipmentChange.title));
      await tester.pumpAndSettle();
      expect(find.byType(HospitalCareForm), findsOneWidget);
      expect(find.text('Cambio de equipo'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Guardar orden de cuidados'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
    },
  );
}

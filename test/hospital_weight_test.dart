import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/hospital/domain/hospital_models.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_weight_view_model.dart';
import 'package:vetdosis_pro/modules/hospital/presentation/hospital_weight_screen.dart';
import 'package:vetdosis_pro/modules/patients/domain/recorded_weight.dart';
import 'clinical_screen_contract_test.dart' show ContractClinical;
import 'hospital_test.dart' show FakeHospital, member, stay, noon;

class WeightClinical extends ContractClinical {
  final entries = <Map<String, dynamic>>[];
  final operations = <String>[];
  final caseData = ClinicalCase({
    'id': 'case',
    'clinic_id': 'a',
    'patient_id': 'patient-a',
    'title': 'Caso ficticio',
  });
  bool failWrite = false;
  Completer<void>? pendingBundle;
  @override
  Future<List<ClinicalCase>> cases(String clinicId, String? patientId) async {
    reads++;
    return [caseData];
  }

  @override
  Future<ClinicalBundle> bundle(String caseId) async {
    if (pendingBundle != null) await pendingBundle!.future;
    return ClinicalBundle(caseData, [], entries, [], [], []);
  }

  @override
  Future<void> observation(
    String caseId,
    Map<String, dynamic> data,
    String operationId,
  ) async {
    writes.add(data);
    operations.add(operationId);
    if (failWrite) throw StateError('uncertain_response');
  }
}

Map<String, dynamic> entry({String id = 'w', String? replaces, DateTime? at}) =>
    {
      'id': id,
      'clinic_id': 'a',
      'case_id': 'case',
      'kind': 'weight',
      'value': '10.250000000',
      'unit': 'kg',
      'observed_at': (at ?? noon).toIso8601String().replaceAll('Z', '+00:00'),
      'performed_by': 'measured-by',
      'recorded_by': 'recorded-by',
      'created_at': noon.add(const Duration(hours: 1)).toIso8601String(),
      'replaces_id': ?replaces,
    };
HospitalWeightViewModel model(
  WeightClinical r,
  FakeHospital h, {
  bool Function()? current,
}) => HospitalWeightViewModel(
  r,
  h,
  member(ClinicRole.auxiliar),
  stay(),
  now: () => noon.add(const Duration(hours: 2)),
  contextIsCurrent: current,
);

void main() {
  test('missing contract on first load never reads patient rows', () async {
    final r = WeightClinical()..missing = true, m = model(r, FakeHospital());
    addTearDown(m.dispose);
    await m.load();
    expect(r.reads, 0);
    expect(m.error, isNotNull);
  });

  test(
    'loads exact weight with PostgreSQL timestamps; corrections replace selection',
    () async {
      final r = WeightClinical()..entries.add(entry()), h = FakeHospital();
      final m = model(r, h);
      addTearDown(m.dispose);
      await m.load();
      final original = m.weights.single;
      expect(original.kg, '10.250000000');
      expect(original.observedAt, noon);
      expect(original.performedBy, 'measured-by');
      expect(original.recordedBy, 'recorded-by');
      expect(m.hasWeightToday, true);
      expect(m.canRecord, false); // No implicit case selection.
      r.entries.add(entry(id: 'corrected', replaces: 'w'));
      expect(await m.validateWeight(original), false);
      expect(m.weights.single.id, 'corrected');
      expect(r.entries.length, 2); // Immutable originals retained.
    },
  );
  test(
    'only admission-period observations count, using observation date',
    () async {
      final r = WeightClinical()
            ..entries.addAll([
              entry(id: 'before', at: noon.subtract(const Duration(days: 1))),
              entry(id: 'future', at: noon.add(const Duration(days: 1))),
            ]),
          m = model(r, FakeHospital());
      addTearDown(m.dispose);
      await m.load();
      expect(m.weights, isEmpty);
      expect(m.hasWeightToday, false);
    },
  );
  test('rejects invalid persisted dates and timezone-free input', () {
    for (final text in [
      '2026-02-30T00:00:00Z',
      '2026-10-07T12:00:00',
      '2026-10-07T12:00:00+24:00',
    ]) {
      expect(() => recordedWeightInstant(text), throwsFormatException);
    }
    expect(recordedWeightInstant('2026-10-07T06:00:00-06:00'), noon);
  });
  test(
    'record requires fresh explicit permission and fixes performer to self',
    () async {
      final r = WeightClinical()..actions['observe'] = true,
          m = model(r, FakeHospital());
      addTearDown(m.dispose);
      await m.load(caseId: 'case');
      expect(m.canRecord, true);
      await m.record(
        '10,25',
        noon.toIso8601String(),
        'Medición ficticia',
        'same-op',
      );
      expect(r.writes.single['performed_by'], 'user-a');
      expect(r.writes.single['value'], '10.25');
      expect(r.operations, ['same-op']);
      r.actions['observe'] = false;
      await expectLater(
        m.record('11', noon.toIso8601String(), '', 'next-op'),
        throwsFormatException,
      );
      expect(r.writes.length, 1);
      expect(m.weights, isEmpty);
    },
  );
  test('invalid values and dates never write', () async {
    final r = WeightClinical()..actions['observe'] = true,
        m = model(r, FakeHospital());
    addTearDown(m.dispose);
    await m.load(caseId: 'case');
    for (final kg in ['0', '-1', 'NaN', '1e3']) {
      await expectLater(
        m.record(kg, noon.toIso8601String(), '', 'op'),
        throwsFormatException,
      );
    }
    for (final at in [
      noon.subtract(const Duration(seconds: 1)),
      noon.add(const Duration(days: 1)),
    ]) {
      await expectLater(
        m.record('1', at.toIso8601String(), '', 'op'),
        throwsFormatException,
      );
    }
    expect(r.writes, isEmpty);
  });
  test('uncertain retries retain supplied operation identity', () async {
    final r = WeightClinical()
          ..actions['observe'] = true
          ..failWrite = true,
        m = model(r, FakeHospital());
    addTearDown(m.dispose);
    await m.load(caseId: 'case');
    await expectLater(
      m.record('10', noon.toIso8601String(), '', 'retry-op'),
      throwsFormatException,
    );
    r.failWrite = false;
    await m.record('10', noon.toIso8601String(), '', 'retry-op');
    expect(r.operations, ['retry-op', 'retry-op']);
    expect(r.writes.first, r.writes.last);
  });
  test(
    'missing/unknown/denied workspace clears data without legacy fallback',
    () async {
      final r = WeightClinical()..entries.add(entry()),
          m = model(r, FakeHospital());
      addTearDown(m.dispose);
      await m.load();
      expect(m.weights, isNotEmpty);
      r.missing = true;
      await m.load();
      expect(m.error, isNotNull);
      expect(m.weights, isEmpty);
      r.missing = false;
      r.schemaVersion = 2;
      await m.load();
      expect(m.error, isNotNull);
      r.schemaVersion = 1;
      r.denied = true;
      await m.load();
      expect(m.error, isNotNull);
      expect(m.canRecord, false);
    },
  );
  test(
    'rejects mismatched clinic, patient, case and observation scopes',
    () async {
      for (final key in ['clinic_id', 'patient_id', 'id']) {
        final r = WeightClinical(), m = model(r, FakeHospital());
        addTearDown(m.dispose);
        r.caseData.data[key] = 'other';
        await m.load(caseId: 'case');
        expect(m.error, isNotNull);
        expect(m.weights, isEmpty);
      }
      for (final key in ['clinic_id', 'case_id', 'unit']) {
        final r = WeightClinical()..entries.add(entry()..[key] = 'other'),
            m = model(r, FakeHospital());
        addTearDown(m.dispose);
        await m.load();
        expect(m.error, isNotNull);
      }
    },
  );
  test('discharge and context revocation invalidate selected weight', () async {
    var current = true;
    final r = WeightClinical()..entries.add(entry()),
        h = FakeHospital(),
        m = model(r, h, current: () => current);
    addTearDown(m.dispose);
    await m.load();
    final weight = m.weights.single;
    current = false;
    expect(await m.validateWeight(weight), false);
    expect(m.weights, isEmpty);
    current = true;
    h.snapshot = HospitalSnapshot([], []);
    expect(await m.validateWeight(weight), false);
  });
  test('serializes loads/writes and ignores disposed response', () async {
    final r = WeightClinical()..pendingBundle = Completer<void>(),
        m = model(r, FakeHospital());
    final loading = m.load(caseId: 'case');
    await Future<void>.delayed(Duration.zero);
    await m.load(caseId: 'other');
    expect(m.selectedCaseId, 'case');
    await expectLater(
      m.record('1', noon.toIso8601String(), '', 'op'),
      throwsFormatException,
    );
    m.dispose();
    r.pendingBundle!.complete();
    await loading;
    expect(m.weights, isEmpty);
    expect(r.writes, isEmpty);
  });
  testWidgets(
    'weight screen at 320 dp requests case explicitly and shows authors',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final r = WeightClinical()
        ..actions['observe'] = true
        ..entries.add(entry());
      await t.pumpWidget(
        MaterialApp(
          home: HospitalWeightScreen(
            clinical: r,
            hospital: FakeHospital(),
            member: member(ClinicRole.auxiliar),
            stay: stay(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Registrar peso'),
            )
            .onPressed,
        isNull,
      );
      await t.scrollUntilVisible(
        find.textContaining('measured-by'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('measured-by'), findsOneWidget);
      await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
      expect(find.text('Revisar peso para cálculo'), findsNothing);
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Caso ficticio').last);
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Registrar peso'),
            )
            .onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
    },
  );
}

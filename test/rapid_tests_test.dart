import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_models.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_repository.dart';
import 'package:vetdosis_pro/modules/forms/clinical/clinical_screen.dart';
import 'package:vetdosis_pro/modules/forms/clinical/rapid_tests/rapid_test_repository.dart';
import 'package:vetdosis_pro/modules/forms/clinical/rapid_tests/rapid_test_view_model.dart';
import 'package:vetdosis_pro/modules/forms/clinical/rapid_tests/rapid_test_screen.dart';
import 'clinical_screen_contract_test.dart'
    show ContractClinical, NoLegacyStaff;

const member = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Synthetic',
  userId: 'person',
  role: ClinicRole.admin,
);
final caseData = ClinicalCase({
  'id': 'case',
  'patient_id': 'patient',
  'patient_name': 'Paciente sintético',
  'title': 'Caso sintético',
});
Map<String, dynamic> data() => {
  'test_name': 'Kit sintético',
  'c_band': 'seen',
  't_band': 'not_seen',
  'result': 'Descripción sintética',
  'observed_at': '2026-10-24T12:00:00Z',
};
Map<String, dynamic> record({String id = 'original', String? replaces}) => {
  ...validateRapidTest(data()),
  'id': id,
  'clinic_id': 'clinic',
  'case_id': 'case',
  'recorded_by': 'person',
  'created_at': '2026-10-24T13:00:00+00:00',
  'photo_path': null,
  'replaces_id': replaces,
  'correction_reason': replaces == null ? null : 'Corrección sintética',
};

class RapidFake implements RapidTestRepository {
  Map<String, dynamic> value = {
    'schema_version': 1,
    'clinic_id': 'clinic',
    'case_id': 'case',
    'patient_id': 'patient',
    'actor_id': 'person',
    'actions': {'record': true, 'correct': true, 'photo': false},
    'records': <Map<String, dynamic>>[],
  };
  Completer<Map<String, dynamic>>? pending;
  final writes = <Map<String, dynamic>>[];
  final operations = <String>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> workspace(String caseId) async =>
      pending == null ? value : pending!.future;
  @override
  Future<void> add(
    String caseId,
    Map<String, dynamic> payload,
    String operation, {
    RapidTestPhoto? photo,
  }) async {
    writes.add(payload);
    operations.add(operation);
    if (fail) throw StateError('uncertain_response');
  }

  @override
  Future<Uint8List> photo(String path) async => Uint8List(0);
}

class RapidClinical extends ContractClinical implements RapidTestProvider {
  @override
  final RapidTestRepository rapidTests = RapidFake();
}

void main() {
  test('manual observations never imply an interpretation', () {
    final result = validateRapidTest(data());
    expect(result['interpretation'], '');
    expect(result['result'], 'Descripción sintética');
    for (final invalid in [
      {...data()}..remove('c_band'),
      {...data(), 't_band': 'positive'},
      {...data(), 'result': ''},
      {...data(), 'observed_at': '2026-02-30T12:00:00Z'},
      {...data(), 'observed_at': '2026-10-24T12:00:00'},
      {...data(), 'replaces_id': 'original'},
      {...data(), 'test_name': List.filled(301, 'x').join()},
    ]) {
      expect(() => validateRapidTest(invalid), throwsFormatException);
    }
  });
  test('photo bytes are bounded and match JPEG/PNG signature', () {
    expect(() => RapidTestPhoto(Uint8List(0), 'png'), throwsFormatException);
    expect(
      () => RapidTestPhoto(Uint8List(8000001), 'png'),
      throwsFormatException,
    );
    expect(
      () => RapidTestPhoto(Uint8List.fromList([1, 2, 3]), 'jpg'),
      throwsFormatException,
    );
    final bytes = Uint8List.fromList([255, 216, 255, 0]);
    final photo = RapidTestPhoto(bytes, 'jpg');
    bytes[0] = 0;
    expect(photo.bytes.first, 255);
    expect(photo.digest.length, 64);
  });
  test(
    'unknown schema, actor, clinic, patient or case clears all data and actions',
    () async {
      for (final mismatch in [
        {'schema_version': 2},
        {'actor_id': 'someone'},
        {'clinic_id': 'foreign'},
        {'patient_id': 'other'},
        {'case_id': 'other'},
        {
          'actions': {'record': true},
        },
        {
          'records': [
            {...record(), 'case_id': 'other'},
          ],
        },
      ]) {
        final repo = RapidFake();
        final active = RapidTestViewModel(repo, member, caseData);
        await active.load();
        expect(active.can('record'), true);
        repo.value = {...repo.value, ...mismatch};
        await active.load();
        expect(active.records, isEmpty);
        expect(active.can('record'), false);
        expect(active.error, isNotNull);
        active.dispose();
      }
    },
  );
  test('revoked permissions deny saving despite visual admin role', () async {
    final repo = RapidFake();
    final active = RapidTestViewModel(repo, member, caseData);
    addTearDown(active.dispose);
    await active.load();
    repo.value['actions'] = {'record': false, 'correct': false, 'photo': false};
    await expectLater(active.add(data(), 'operation'), throwsStateError);
    expect(repo.writes, isEmpty);
  });
  test(
    'corrections preserve original history and deny stale second correction',
    () async {
      final repo = RapidFake();
      repo.value['records'] = [
        record(),
        record(id: 'correction', replaces: 'original'),
      ];
      final model = RapidTestViewModel(repo, member, caseData);
      addTearDown(model.dispose);
      await model.load();
      expect(model.records.length, 2);
      expect(model.replaced('original'), true);
      await expectLater(
        model.add({
          ...data(),
          'replaces_id': 'original',
          'correction_reason': 'revisión',
        }, 'op'),
        throwsStateError,
      );
      expect(repo.writes, isEmpty);
      await model.add({
        ...data(),
        'replaces_id': 'correction',
        'correction_reason': 'revisión',
      }, 'op2');
      expect(repo.writes.single['replaces_id'], 'correction');
    },
  );
  test(
    'late responses after dispose cannot restore records or permissions',
    () async {
      final repo = RapidFake()..pending = Completer<Map<String, dynamic>>();
      final model = RapidTestViewModel(repo, member, caseData);
      final loading = model.load();
      model.dispose();
      repo.pending!.complete(repo.value);
      await loading;
      expect(model.records, isEmpty);
      expect(model.can('record'), false);
    },
  );
  testWidgets(
    '320dp manual entry has no band or interpretation defaults; retries retain identity',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = RapidFake()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: RapidTestScreen(
            repository: repo,
            member: member,
            caseData: caseData,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar prueba rápida'));
      await tester.pumpAndSettle();
      expect(find.text('Visible'), findsNothing);
      Future<void> reveal(Finder finder) async {
        final scrollable = find.byType(Scrollable).first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
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

      await text('Prueba / kit', 'Kit sintético');
      final at = find.text('Fecha y hora reales de lectura *');
      await reveal(at);
      await tester.tap(at);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      for (final label in ['Banda C observada *', 'Banda T observada *']) {
        final f = find.widgetWithText(DropdownButtonFormField<String>, label);
        await reveal(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
        await tester.tap(find.text('No puedo determinarlo').last);
        await tester.pumpAndSettle();
      }
      await text('Resultado leído', 'Captura sintética');
      Future<void> save() async {
        final button = find.widgetWithText(FilledButton, 'Guardar');
        await reveal(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await save();
      await save();
      expect(repo.operations.length, 2);
      expect(repo.operations.toSet().length, 1);
      expect(repo.writes.first['interpretation'], '');
      await text('Resultado leído', 'Captura revisada');
      await save();
      expect(repo.operations.toSet().length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('rapid tests are reachable from the selected clinical case', (
    tester,
  ) async {
    final repo = RapidClinical();
    await tester.pumpWidget(
      MaterialApp(
        home: ClinicalScreen(
          repository: repo,
          forms: NoLegacyStaff(),
          member: member,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paciente · Historia'));
    await tester.pumpAndSettle();
    final button = find.text('Pruebas rápidas del caso');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    // The synthetic case's patient id matches the rapid-test fixture.
    expect(find.text('Pruebas rápidas'), findsOneWidget);
  });
  test(
    'Supabase read contract uses the case-scoped RPC and exposes provider',
    () async {
      final requests = <String>[];
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic',
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          expect(jsonDecode(request.body), {'p_case': 'case'});
          return http.Response(
            jsonEncode(RapidFake().value),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabaseClinicalRepository(client);
      final result = await repo.rapidTests.workspace('case');
      expect(result['case_id'], 'case');
      expect(requests, ['/rest/v1/rpc/clinical_rapid_tests_workspace']);
    },
  );
  test(
    'Supabase saves own manual result and immutable photo with identical retry path',
    () async {
      final writes = <Map<String, dynamic>>[], paths = <String>[];
      int uploads = 0;
      final client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          Object body;
          int status = 200;
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'synthetic-access',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'synthetic-refresh',
              'user': {
                'id': 'person',
                'aud': 'authenticated',
                'email': 'synthetic@example.test',
                'created_at': '2026-10-24T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            };
          } else if (request.url.path.endsWith(
            'clinical_rapid_tests_workspace',
          )) {
            body = {
              ...RapidFake().value,
              'actions': {'record': true, 'correct': false, 'photo': true},
            };
          } else if (request.url.path.contains(
            '/storage/v1/object/rapid-test-photos/',
          )) {
            paths.add(request.url.path);
            uploads++;
            if (uploads == 1) {
              expect(request.headers['x-upsert'], 'false');
              body = {'Key': 'synthetic'};
            } else {
              status = 409;
              body = {
                'statusCode': '409',
                'error': 'Duplicate',
                'message': 'Already exists',
              };
            }
          } else if (request.url.path.endsWith('clinical_rapid_test_add')) {
            writes.add(Map<String, dynamic>.from(jsonDecode(request.body)));
            body = 'record-id';
          } else {
            throw StateError('Unexpected request: ${request.url.path}');
          }
          return http.Response(
            jsonEncode(body),
            status,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'synthetic@example.test',
        password: 'synthetic-local-password',
      );
      final repo = SupabaseRapidTestRepository(client);
      final photo = RapidTestPhoto(
        Uint8List.fromList([255, 216, 255, 0]),
        'jpg',
      );
      final operation = List.filled(48, 'a').join();
      await repo.add('case', data(), operation, photo: photo);
      await repo.add('case', data(), operation, photo: photo);
      expect(paths.length, 2);
      expect(paths.toSet().length, 1);
      expect(writes.length, 2);
      expect(writes.first, writes.last);
      expect(writes.first['p_operation'], operation);
      final payload = writes.first['p_data'] as Map;
      expect(payload['interpretation'], '');
      expect(payload.containsKey('recorded_by'), false);
      expect(
        payload['photo_path'],
        'clinic/case/$operation-${photo.digest}.jpg',
      );
    },
  );
}

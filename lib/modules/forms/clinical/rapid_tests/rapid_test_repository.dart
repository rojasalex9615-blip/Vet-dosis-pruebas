import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../clinical_models.dart';

const rapidBandLabels = {
  'seen': 'Visible',
  'not_seen': 'No visible',
  'uncertain': 'No puedo determinarlo',
  'not_applicable': 'No aplica a esta prueba',
};

/// Returns trimmed manual test fields with a normalized UTC observation time.
///
/// Requires explicit C/T band choices and a result; interpretation may be empty.
/// Throws [FormatException] for invalid fields, a timestamp without seconds or
/// a trailing Z, or a replacement without a correction reason.
Map<String, dynamic> validateRapidTest(Map<String, dynamic> data) {
  String field(String key, int max, {bool required = false}) {
    final value = data[key] ?? '';
    if (value is! String ||
        value.length > max ||
        (required && value.trim().isEmpty)) {
      throw FormatException('Revisa $key (máximo $max caracteres).');
    }
    return value.trim();
  }

  for (final key in ['c_band', 't_band']) {
    if (!rapidBandLabels.containsKey(data[key])) {
      throw const FormatException('Selecciona explícitamente ambas bandas.');
    }
  }
  return {
    'test_name': field('test_name', 300, required: true),
    'sample': field('sample', 1000),
    'c_band': data['c_band'],
    't_band': data['t_band'],
    'result': field('result', 4000, required: true),
    'interpretation': field('interpretation', 4000),
    'notes': field('notes', 4000),
    'observed_at': clinicalInstant(
      field('observed_at', 40, required: true),
    ).toIso8601String(),
    if (data['replaces_id'] != null)
      'replaces_id': field('replaces_id', 36, required: true),
    if (data['replaces_id'] != null)
      'correction_reason': field('correction_reason', 1000, required: true),
  };
}

class RapidTestPhoto {
  /// Copies [source] into immutable bytes, checking size and file signature.
  ///
  /// Throws [FormatException] unless there are 1 to 8,000,000 bytes and
  /// [extension] is `png` or `jpg` with the matching header. Does not decode images.
  RapidTestPhoto(Uint8List source, this.extension)
    : bytes = Uint8List.fromList(source).asUnmodifiableView() {
    if (bytes.isEmpty ||
        bytes.length > 8000000 ||
        !['png', 'jpg'].contains(extension)) {
      throw const FormatException(
        'Selecciona una foto PNG/JPEG de máximo 8 MB.',
      );
    }
    final png =
        bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
    final jpg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!(extension == 'png' ? png : jpg)) {
      throw const FormatException(
        'El contenido no corresponde a una foto PNG/JPEG.',
      );
    }
  }
  final Uint8List bytes;
  final String extension;
  String get digest => sha256.convert(bytes).toString();
}

abstract interface class RapidTestProvider {
  RapidTestRepository get rapidTests;
}

abstract interface class RapidTestRepository {
  /// Loads manual results and current action permissions for a clinical case.
  Future<Map<String, dynamic>> workspace(String caseId);
  /// Appends a result or correction, optionally attaching photo evidence.
  ///
  /// Reuse [operation] for an identical retry; corrections retain the original.
  Future<void> add(
    String caseId,
    Map<String, dynamic> data,
    String operation, {
    RapidTestPhoto? photo,
  });
  /// Downloads evidence from its storage path; storage errors propagate.
  Future<Uint8List> photo(String path);
}

class SupabaseRapidTestRepository implements RapidTestRepository {
  SupabaseRapidTestRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> workspace(String caseId) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'clinical_rapid_tests_workspace',
              params: {'p_case': caseId},
            )
            as Map,
      );
  /// Validates the result, rechecks access, then uploads evidence before saving.
  ///
  /// Photos require a 48-character lowercase hexadecimal [operation]. Identical
  /// retries reuse the upload path; duplicate uploads are accepted. A failed
  /// save can leave the uploaded object in storage. [FormatException] from
  /// validation, [StateError] for denied access, and other storage or RPC errors
  /// propagate.
  @override
  Future<void> add(
    String caseId,
    Map<String, dynamic> data,
    String operation, {
    RapidTestPhoto? photo,
  }) async {
    final payload = validateRapidTest(data);
    final current = await workspace(caseId);
    if (current['schema_version'] != 1 ||
        current['case_id'] != caseId ||
        current['actor_id'] != client.auth.currentUser?.id ||
        current['actions']?[payload.containsKey('replaces_id')
                ? 'correct'
                : 'record'] !=
            true) {
      throw StateError('rapid_test_access_denied');
    }
    if (photo != null) {
      if (current['actions']?['photo'] != true ||
          !RegExp(r'^[0-9a-f]{48}$').hasMatch(operation)) {
        throw StateError('rapid_test_photo_denied');
      }
      final path =
          '${current['clinic_id']}/$caseId/$operation-${photo.digest}.${photo.extension}';
      try {
        await client.storage
            .from('rapid-test-photos')
            .uploadBinary(
              path,
              photo.bytes,
              fileOptions: FileOptions(
                contentType: photo.extension == 'png'
                    ? 'image/png'
                    : 'image/jpeg',
                upsert: false,
              ),
            );
      } on StorageException catch (e) {
        // Same immutable path on identical retries. The RPC checks owner, case and metadata.
        if (e.statusCode != '409' && e.error != 'Duplicate') rethrow;
      }
      payload['photo_path'] = path;
    }
    await client.rpc(
      'clinical_rapid_test_add',
      params: {'p_case': caseId, 'p_data': payload, 'p_operation': operation},
    );
  }

  @override
  Future<Uint8List> photo(String path) =>
      client.storage.from('rapid-test-photos').download(path);
}

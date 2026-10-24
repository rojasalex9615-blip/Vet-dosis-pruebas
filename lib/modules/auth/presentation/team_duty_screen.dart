import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart';
import '../domain/auth_repository.dart';
import '../domain/clinic_membership.dart';
import 'auth_view_model.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';

Map<String, dynamic> dutyFormData(Map<String, dynamic> input) {
  final data = Map<String, dynamic>.from(input)..remove('user_id');
  for (final prefix in ['start', 'end']) {
    final day = '${data['${prefix}_day']}';
    final parsed = DateTime.tryParse('${day}T00:00:00Z');
    final time = '${data.remove('${prefix}_time')}';
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != day ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time)) {
      throw const FormatException('Usa fecha AAAA-MM-DD y hora HH:mm válidas.');
    }
    final parts = time.split(':');
    data['${prefix}_minute'] = int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
  if (data['cover_id'] == '') data.remove('cover_id');
  return data;
}

Map<String, dynamic> dutyEntryInitial(Map<String, dynamic> row) {
  tzdata.initializeTimeZones();
  final location = tz.getLocation(row['zone'] as String);
  final result = <String, dynamic>{
    'replaces_id': row['id'],
    'cover_id': row['cover_id'] ?? '',
  };
  for (final prefix in ['start', 'end']) {
    final instant = tz.TZDateTime.from(
      DateTime.parse(
        row[prefix == 'start' ? 'starts_at' : 'ends_at'] as String,
      ),
      location,
    );
    String two(int n) => n.toString().padLeft(2, '0');
    result['${prefix}_day'] =
        '${instant.year}-${two(instant.month)}-${two(instant.day)}';
    result['${prefix}_time'] = '${two(instant.hour)}:${two(instant.minute)}';
  }
  return result;
}

class TeamDutyScreen extends StatefulWidget {
  const TeamDutyScreen({super.key, required this.model, required this.clinic});
  final AuthViewModel model;
  final ClinicMembership clinic;
  @override
  State<TeamDutyScreen> createState() => _TeamDutyScreenState();
}

class _TeamDutyScreenState extends State<TeamDutyScreen> {
  Map<String, dynamic>? snapshot;
  String? error;
  bool busy = false;
  bool get allowed =>
      !widget.model.offline &&
      widget.model.repository is TeamDutyRepository &&
      widget.model.active?.clinicId == widget.clinic.clinicId &&
      widget.model.memberships.any((m) => m.clinicId == widget.clinic.clinicId);
  TeamDutyRepository get repository =>
      widget.model.repository as TeamDutyRepository;
  bool get admin => snapshot?['admin'] == true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!allowed || busy) return;
    setState(() {
      busy = true;
      snapshot = null;
      error = null;
    });
    try {
      final result = await repository.dutyWorkspace(widget.clinic.clinicId);
      if (result['version'] != 1 ||
          result['clinic_id'] != widget.clinic.clinicId ||
          result['actor_id'] != widget.model.repository.userId ||
          result['admin'] is! bool ||
          result['members'] is! List ||
          result['entries'] is! List) {
        throw const FormatException('Contrato de horarios desconocido.');
      }
      if (mounted && allowed) setState(() => snapshot = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudieron cargar los horarios. Revisa la conexión y que esté instalada la actualización de equipo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(String kind, [Map<String, dynamic>? row]) async {
    if (!allowed || snapshot == null) return;
    final members = {
      for (final m in snapshot!['members'] as List)
        m['id'] as String: m['name'] as String,
    };
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: row != null
              ? 'Editar horario / permiso'
              : kind == 'shift'
              ? 'Agregar turno'
              : 'Autorizar falta y cobertura',
          reviewText:
              'Captura la zona horaria de la clínica y ambas fechas (también para turnos nocturnos). La cobertura no otorga permisos clínicos. Las faltas prevalecen sobre los turnos. Evita incluir diagnósticos en el motivo.',
          initial: {
            'kind': kind,
            'user_id': row?['user_id'] ?? widget.model.repository.userId,
            'zone': row?['zone'] ?? '',
            if (row != null) ...dutyEntryInitial(row),
          },
          fields: [
            if (row == null && admin)
              RxField(
                'user_id',
                'Integrante',
                type: 'select',
                options: members,
                required: true,
              ),
            const RxField(
              'start_day',
              'Fecha de inicio (AAAA-MM-DD)',
              required: true,
            ),
            const RxField(
              'start_time',
              'Hora de inicio (HH:mm)',
              required: true,
            ),
            const RxField(
              'end_day',
              'Fecha de fin (AAAA-MM-DD)',
              required: true,
            ),
            const RxField('end_time', 'Hora de fin (HH:mm)', required: true),
            const RxField(
              'zone',
              'Zona IANA (ej. America/Mexico_City)',
              required: true,
            ),
            if (kind == 'absence')
              RxField(
                'cover_id',
                'Quién cubre (opcional)',
                type: 'select',
                options: {'': 'Sin cobertura asignada', ...members},
              ),
            const RxField(
              'reason',
              'Motivo del registro o cambio',
              required: true,
            ),
          ],
          submit: (data, operation) async {
            if (!allowed) throw StateError('Actualiza tu sesión.');
            await repository.saveDuty(
              widget.clinic.clinicId,
              data['user_id'] as String,
              dutyFormData(data),
              operation,
            );
          },
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> cancel(Map<String, dynamic> row) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: 'Cancelar horario / permiso',
          fields: const [
            RxField('reason', 'Motivo de cancelación', required: true),
          ],
          submit: (data, operation) async {
            if (!allowed) throw StateError('Actualiza tu sesión.');
            await repository.cancelDuty(
              widget.clinic.clinicId,
              row['id'] as String,
              data['reason'] as String,
              operation,
            );
          },
        ),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Equipo · horarios y faltas')),
      body: !allowed
          ? const Center(
              child: Text(
                'Actualiza la sesión de esta clínica para ver los horarios.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Cada integrante registra sus turnos. El administrador autoriza faltas, registra su motivo y elige quién cubre. Sin turno ni cobertura vigente no se asignan avisos.',
                ),
                const Text(
                  'Los avisos por teléfono y WhatsApp requieren activar el envío del servidor en la integración final.',
                ),
                OutlinedButton(
                  onPressed: busy ? null : load,
                  child: const Text('Actualizar horarios'),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                if (snapshot != null) ...[
                  if (admin &&
                      (snapshot!['qualified_primary_on_duty'] == 0 ||
                          snapshot!['qualified_mvz_on_duty'] == 0))
                    const Text(
                      'Atención: falta personal con permisos de avisos o MVZ responsable habilitado en turno. Revisa horarios, cobertura y permisos.',
                    ),
                  FilledButton(
                    onPressed: () => edit('shift'),
                    child: const Text('Agregar turno'),
                  ),
                  if (admin)
                    OutlinedButton(
                      onPressed: () => edit('absence'),
                      child: const Text('Autorizar falta y elegir cobertura'),
                    ),
                  for (final m in snapshot!['members'] as List)
                    ListTile(
                      title: Text(m['name'] as String),
                      subtitle: Text(
                        m['on_duty'] == true ? 'En turno' : 'Fuera de turno',
                      ),
                    ),
                  const Text('Horarios e historial (horas mostradas en UTC)'),
                  for (final raw in snapshot!['entries'] as List)
                    Builder(
                      builder: (context) {
                        final row = Map<String, dynamic>.from(raw as Map);
                        final names = {
                          for (final m in snapshot!['members'] as List)
                            m['id']: m['name'],
                        };
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${names[row['user_id']] ?? row['user_id']} · ${row['kind'] == 'shift' ? 'Turno' : 'Falta autorizada'}${row['cancelled'] == true ? ' · Cancelado' : ''}',
                                ),
                                Text(
                                  '${DateTime.parse(row['starts_at'] as String).toUtc()} → ${DateTime.parse(row['ends_at'] as String).toUtc()}',
                                ),
                                Text(
                                  'Zona de captura: ${row['zone']} · Motivo: ${row['reason']}',
                                ),
                                if (row['cover_id'] != null)
                                  Text(
                                    'Cubre: ${names[row['cover_id']] ?? row['cover_id']}',
                                  ),
                                if (row['cancelled'] == true)
                                  Text(
                                    'Cancelación: ${row['cancel_reason']} · ${row['cancelled_at']}',
                                  ),
                                if (row['can_edit'] == true)
                                  Wrap(
                                    children: [
                                      TextButton(
                                        onPressed: () =>
                                            edit(row['kind'] as String, row),
                                        child: const Text('Editar'),
                                      ),
                                      TextButton(
                                        onPressed: () => cancel(row),
                                        child: const Text('Cancelar'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
    ),
  );
}

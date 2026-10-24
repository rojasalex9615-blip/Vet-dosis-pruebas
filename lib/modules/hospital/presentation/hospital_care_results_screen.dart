import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/hospital_repository.dart';
import '../domain/hospital_care_result.dart';

class HospitalCareResultsScreen extends StatefulWidget {
  const HospitalCareResultsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.taskId,
  });
  final HospitalCareResultRepository repository;
  final ClinicMembership member;
  final String? taskId;
  @override
  State<HospitalCareResultsScreen> createState() =>
      _HospitalCareResultsScreenState();
}

class _HospitalCareResultsScreenState extends State<HospitalCareResultsScreen> {
  HospitalCareWorkspace? workspace;
  bool busy = false, opening = false;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    workspace = null;
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) return;
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
      workspace = null;
    });
    try {
      final raw = await widget.repository.careWorkspace(
        widget.member.clinicId,
        widget.taskId,
      );
      if (!mounted || current != generation) return;
      final result = HospitalCareWorkspace.read(
        raw,
        widget.member.clinicId,
        widget.member.userId,
        widget.taskId,
      );
      setState(() => workspace = result);
    } catch (_) {
      if (mounted && current == generation) {
        setState(
          () => error =
              'No se pudieron consultar los resultados. Revisa permisos, conexión y versión del servidor.',
        );
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  Future<void> entry({Map<String, dynamic>? correction}) async {
    if (opening || busy || widget.taskId == null) return;
    setState(() => opening = true);
    try {
      await load();
      final w = workspace;
      if (!mounted ||
          w == null ||
          !(correction == null ? w.canRecord : w.canCorrect) ||
          (correction != null &&
              (!w.records.any((r) => r['id'] == correction['id']) ||
                  w.replaced(correction['id'])))) {
        return;
      }
      final kind = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Cuidado que realizaste'),
          children: [
            for (final e in careResultKinds.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e.key),
                child: Text(e.value),
              ),
          ],
        ),
      );
      if (!mounted || kind == null) return;
      final task = w.task!;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RxEntryScreen(
            title: correction == null
                ? 'Resultado de mi cuidado'
                : 'Corregir mi resultado',
            reviewText:
                '${task['patient_name']} · ${task['label']}\n${task['instructions']}\n'
                'Registra solo el cuidado que realizaste. El tipo se elige manualmente; no se infiere de la indicación. '
                'La cantidad consumida puede ser cero. Registrar el cuidado no acredita consumo completo. '
                '${task['state'] == 'pending' ? 'Guardar también confirma la tarea en una sola operación.' : 'La tarea ya está confirmada; se anexa información sin volver a realizarla.'}'
                '${correction == null ? '' : '\nLa corrección conserva el registro original y requiere motivo.'}',
            fields: [
              const RxField(
                'observed_at',
                'Fecha y hora reales del cuidado',
                type: 'local_instant',
                required: true,
              ),
              if (kind == 'feeding') ...[
                const RxField(
                  'offered',
                  'Cantidad realmente ofrecida',
                  required: true,
                ),
                const RxField(
                  'consumed',
                  'Cantidad realmente consumida (puede ser 0)',
                  required: true,
                ),
                const RxField(
                  'unit',
                  'Unidad de ambas cantidades',
                  type: 'select',
                  options: {'g': 'g', 'ml': 'ml', 'porción': 'porción'},
                  required: true,
                ),
              ],
              const RxField(
                'findings',
                'Hallazgos / dispositivo y sitio / observaciones',
                required: true,
              ),
              if (correction != null)
                const RxField(
                  'correction_reason',
                  'Motivo de corrección',
                  required: true,
                ),
              const RxField(
                'confirmed',
                'Confirmo que yo realicé este cuidado y revisé la captura',
                type: 'checkbox',
                required: true,
              ),
            ],
            submit: (data, operation) => widget.repository.recordCare(
              widget.member.clinicId,
              widget.taskId!,
              task['version'],
              validateCareResult({
                ...data,
                'care_kind': kind,
                if (correction != null) 'replaces_id': correction['id'],
              }),
              operation,
            ),
          ),
        ),
      );
      if (mounted) await load();
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Resultados de cuidados')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Registro manual de alimentación y cuidados. Conserva originales y correcciones; no genera indicaciones clínicas.',
        ),
        OutlinedButton(
          onPressed: busy || opening ? null : load,
          child: const Text('Actualizar resultados'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (workspace?.task != null)
          Text(
            '${workspace!.task!['patient_name']} · ${workspace!.task!['label']}',
          ),
        if (workspace?.canRecord == true)
          FilledButton(
            onPressed: opening ? null : entry,
            child: const Text('Registrar resultado de mi cuidado'),
          ),
        if (workspace != null && workspace!.records.isEmpty)
          const Text('Sin resultados estructurados registrados.'),
        for (final row in workspace?.records ?? <Map<String, dynamic>>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['patient_name']} · ${row['task_label']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(careResultKinds[row['care_kind']]!),
                  if (workspace!.replaced(row['id']))
                    const Text(
                      'Sustituido por corrección · antecedente conservado',
                    ),
                  if (row['care_kind'] == 'feeding')
                    Text(
                      'Ofrecido: ${row['offered']} ${row['unit']} · Consumido: ${row['consumed']} ${row['unit']}',
                    ),
                  Text(row['findings']),
                  Text(
                    'Observado: ${DateTime.parse(row['observed_at']).toLocal()}\nRealizó y registró: ${row['actor_id']}\nServidor: ${DateTime.parse(row['created_at']).toLocal()}',
                  ),
                  if (row['replaces_id'] != null)
                    Text(
                      'Corrige: ${row['replaces_id']} · ${row['correction_reason']}',
                    ),
                  if (widget.taskId != null &&
                      workspace!.canCorrect &&
                      !workspace!.replaced(row['id']))
                    TextButton(
                      onPressed: opening || busy
                          ? null
                          : () => entry(correction: row),
                      child: const Text('Corregir conservando original'),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

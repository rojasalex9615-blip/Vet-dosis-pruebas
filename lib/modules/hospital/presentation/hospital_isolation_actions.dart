import 'package:flutter/material.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/hospital_isolation.dart';
import '../domain/hospital_models.dart';
import '../domain/hospital_repository.dart';
import 'hospital_view_model.dart';

class HospitalIsolationActions {
  HospitalIsolationActions(this.model, this.contextIsCurrent);
  final HospitalViewModel model;
  final bool Function() contextIsCurrent;
  HospitalIsolationRepository get repository =>
      model.repository as HospitalIsolationRepository;
  String get clinic => model.member.clinicId;
  Future<void> save(Future<void> Function() action, String permission) async {
    if (!contextIsCurrent()) {
      throw const FormatException(
        'La cuenta o clínica cambió. Vuelve a abrir hospitalización.',
      );
    }
    if (!model.isolationPermission(permission)) {
      throw const FormatException(
        'Falta el contrato o permiso explícito de aislamiento. Actualiza la hoja.',
      );
    }
    final ok = await model.mutate(action, permission: permission);
    if (!ok) {
      throw FormatException(
        model.error ?? 'Actualiza la hoja y comprueba tus permisos.',
      );
    }
  }

  Future<void> set(
    BuildContext context,
    HospitalStay stay,
    HospitalIsolation? current,
  ) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => RxEntryScreen(
        title: current?.active == true
            ? 'Retirar aislamiento'
            : 'Indicar aislamiento',
        reviewText:
            '${stay.patientName} · Jaula ${stay.cageLabel}\n'
            '${current == null ? 'Captura el protocolo que la clínica revisó, su documento/versión y los pasos de limpieza. No hay protocolos precargados.' : 'Referencia: ${current.reference}\n${current.steps.join('\n')}'}\n'
            'Retirar la bandera no confirma limpieza. Al cambiar de jaula o dar el alta quedarán pendientes los espacios expuestos.',
        fields: [
          const RxField('reason', 'Motivo', type: 'text', required: true),
          if (current == null) ...[
            const RxField(
              'reference',
              'Documento, versión y ubicación del protocolo',
              type: 'text',
              required: true,
            ),
            const RxField(
              'steps',
              'Checklist aprobado por la clínica (un paso por línea)',
              type: 'text',
              required: true,
            ),
          ],
          const RxField(
            'review',
            'Revisé paciente, decisión y protocolo de la clínica',
            type: 'checkbox',
            required: true,
          ),
        ],
        submit: (data, operation) => save(
          () => repository.setIsolation(
            clinic,
            stay,
            !(current?.active ?? false),
            data['reason'] as String,
            current?.reference ?? data['reference'] as String,
            current?.steps ??
                isolationSteps((data['steps'] as String).split('\n')),
            operation,
          ),
          'hospital.isolation.manage',
        ),
      ),
    ),
  );

  Future<void> enter(
    BuildContext context,
    HospitalStay stay,
    HospitalIsolation isolation,
  ) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => RxEntryScreen(
        title: 'Registrar acceso a aislamiento',
        reviewText:
            '${stay.patientName} · Jaula ${stay.cageLabel}\nReferencia: ${isolation.reference}\n${isolation.steps.join('\n')}\nEste registro identifica a la persona que confirma el acceso. No registra tratamientos ni verifica una entrada física.',
        fields: const [
          RxField('note', 'Motivo del acceso', type: 'text', required: true),
          RxField(
            'review',
            'Revisé el paciente y el protocolo; confirmo mi propio acceso',
            type: 'checkbox',
            required: true,
          ),
        ],
        submit: (data, operation) => save(
          () => repository.enterIsolation(
            clinic,
            stay,
            data['note'] as String,
            operation,
          ),
          'hospital.isolation.handle',
        ),
      ),
    ),
  );

  Future<void> clean(
    BuildContext context,
    HospitalIsolationArea area,
  ) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => RxEntryScreen(
        title: 'Confirmar desinfección',
        reviewText:
            '${area.patientName} · ${area.cageLabel}\nÁrea: ${area.id}\nReferencia: ${area.reference}\nLiberada: ${area.releasedAt?.toLocal()}\nMarca únicamente pasos que tú realizaste. La confirmación permite reasignar la jaula si no hay otras limpiezas pendientes.',
        fields: [
          for (var i = 0; i < area.steps.length; i++)
            RxField('step_$i', area.steps[i], type: 'checkbox', required: true),
          const RxField('notes', 'Notas', type: 'text'),
          const RxField(
            'review',
            'Confirmo que realicé todos los pasos y revisé el área',
            type: 'checkbox',
            required: true,
          ),
        ],
        submit: (data, operation) => save(
          () => repository.cleanIsolation(
            clinic,
            area,
            [
              for (var i = 0; i < area.steps.length; i++)
                if (data['step_$i'] == true) area.steps[i],
            ],
            data['notes'] as String? ?? '',
            operation,
          ),
          'hospital.isolation.handle',
        ),
      ),
    ),
  );

  Future<void> history(BuildContext context, String? stay) async {
    try {
      if (!contextIsCurrent()) throw StateError('context_changed');
      final rows = await repository.isolationHistory(clinic, stay);
      if (!context.mounted || !contextIsCurrent()) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Bitácora de aislamiento')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (rows.isEmpty) const Text('Sin movimientos registrados.'),
                for (final r in rows.reversed)
                  ListTile(
                    title: Text(
                      '${r['patient_name']} · ${const {'hospital_isolation_changed': 'Cambio de aislamiento', 'hospital_isolation_entry': 'Acceso registrado', 'hospital_isolation_cleaning_due': 'Desinfección pendiente', 'hospital_isolation_cleaned': 'Desinfección confirmada'}[r['action']] ?? 'Movimiento'}',
                    ),
                    subtitle: Text(
                      '${DateTime.parse(r['at'] as String).toLocal()} · ${r['actor_id']}\n'
                      'Estancia: ${r['stay_id']}\n${historyDetails(Map<String, dynamic>.from(r['details'] as Map))}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo consultar la bitácora. Revisa acceso y conexión.',
            ),
          ),
        );
      }
    }
  }
}

String historyDetails(Map<String, dynamic> details) => [
  if (details['active'] is bool)
    details['active'] == true
        ? 'Aislamiento indicado'
        : 'Bandera de aislamiento retirada',
  if (details['cage'] != null) 'Jaula: ${details['cage']}',
  if (details['reason'] != null) details['reason'],
  if (details['note'] != null) details['note'],
  if (details['reference'] != null) 'Referencia: ${details['reference']}',
  if (details['checks'] is List) ...(details['checks'] as List),
  if (details['notes'] != null) details['notes'],
].join('\n');

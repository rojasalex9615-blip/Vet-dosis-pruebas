import '../../auth/domain/staff_labels.dart';
import '../domain/service_catalog.dart';
import 'appointment_patient_picker.dart';
import '../../backup/domain/backup_archive.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../inventory/domain/inventory_models.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/operations_repository.dart';
import 'operations_view_model.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.onOpenPatient,
    this.onOpenDuty,
    this.initialSection = 'appointments',
  });
  final Future<void> Function(String)? onOpenPatient;
  final VoidCallback? onOpenDuty;
  final OperationsRepository repository;
  final String initialSection;
  final ClinicMembership member;
  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  late final model = OperationsViewModel(
    widget.repository,
    widget.member.clinicId,
  );
  String section = 'appointments', filter = 'pendientes';
  DateTime? calendarDay;
  bool get admin => widget.member.role == ClinicRole.admin;
  Map<String, String> get people => {
    for (final p in model.rows('members'))
      p['user_id'] as String: staffLabel(
        p['user_id'] as String,
        model.rows('people'),
        role: p['role'] as String,
      ),
  };
  String get activeSection {
    if (model.busy && model.data.isEmpty) return 'loading';
    return model.explicitPermissions && !model.sectionAllowed(section)
        ? 'blocked'
        : section;
  }
  String person(String id) => staffLabel(id, model.rows('people'));
  @override
  void initState() {
    super.initState();
    section = widget.initialSection;
    model.load();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> form(
    String title,
    String action,
    List<RxField> fields, {
    Map<String, dynamic> initial = const {},
  }) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: title,
          fields: fields,
          initial: initial,
          submit: (d, op) async {
            if (action == 'appointment' || action == 'appointment_reschedule') {
              validateAppointmentTimes(d);
            }
            try {
              await widget.repository.write(
                widget.member.clinicId,
                action,
                d,
                op,
              );
            } catch (e) {
              throw FormatException(operationError(e));
            }
          },
        ),
      ),
    );
    if (ok == true && mounted) await model.load();
  }

  Future<void> newAppointment() async {
    Map<String, dynamic> patient = {};
    if ((model.explicitPermissions
            ? model.allowed('patient.read')
            : widget.member.role != ClinicRole.estilista) &&
        widget.repository is AppointmentPatientRepository) {
      final selected = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => AppointmentPatientPicker(
            repository: widget.repository as AppointmentPatientRepository,
            clinic: widget.member.clinicId,
          ),
        ),
      );
      if (selected == null || !mounted) return;
      patient = selected;
    }
    await form(
      patient.isEmpty
          ? 'Nueva cita sin expediente'
          : 'Cita para ${patient['name']}',
      'appointment',
      [
        if (patient.isEmpty)
          const RxField('patient_name', 'Paciente', required: true),
        if (patient.isEmpty)
          const RxField('species', 'Especie', required: true),
        const RxField(
          'kind',
          'Tipo',
          type: 'select',
          options: {'consulta': 'Consulta', 'estetica': 'Estética / baño'},
          required: true,
        ),
        RxField(
          'professional_id',
          model.explicitPermissions ? 'Integrante asignado' : 'Profesional',
          type: 'select',
          options: people,
          required: true,
        ),
        const RxField(
          'starts_at',
          'Inicio',
          type: 'local_instant',
          required: true,
        ),
        const RxField('ends_at', 'Fin', type: 'local_instant', required: true),
        const RxField('notes', 'Observaciones'),
      ],
      initial: patient.isEmpty
          ? {}
          : {
              'patient_id': patient['id'],
              'patient_name': patient['name'],
              'species': patient['species'],
            },
    );
  }

  Future<void> medical() async {
    try {
      var profiles = await widget.repository.medical(widget.member.clinicId);
      if (!mounted) return;
      final own = profiles
          .where((p) => p['user_id'] == widget.member.userId)
          .firstOrNull;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RxEntryScreen(
            title: 'Mi ficha médica · acceso restringido',
            initial: Map<String, dynamic>.from(own?['details'] as Map? ?? {}),
            fields: const [
              RxField('blood', 'Grupo sanguíneo'),
              RxField('allergies', 'Alergias'),
              RxField('conditions', 'Antecedentes'),
              RxField('vaccines', 'Vacunación'),
              RxField('emergency', 'Contacto de emergencia'),
              RxField(
                'consent',
                'Consiento el registro; solo yo y el admin de esta clínica podrán consultarlo',
                type: 'checkbox',
                required: true,
              ),
              RxField(
                'erase',
                'Retirar la ficha y su consentimiento',
                type: 'checkbox',
              ),
            ],
            submit: (d, op) async {
              if (d['consent'] != true) {
                throw const FormatException('Confirma tu consentimiento.');
              }
              final erase = d.remove('erase') == true;
              d.remove('consent');
              await widget.repository.medical(
                widget.member.clinicId,
                details: erase ? {} : d,
                consent: true,
              );
            },
          ),
        ),
      );
      if (admin && mounted) {
        profiles = await widget.repository.medical(widget.member.clinicId);
      }
      if (admin && mounted && profiles.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Fichas consentidas del personal'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  for (final p in profiles)
                    ListTile(
                      title: Text(person(p['user_id'] as String)),
                      subtitle: Text('${p['details']}'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Operación de clínica',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'La agenda y los servicios no autorizan procedimientos ni sustituyen el registro clínico.',
        ),
        if (widget.onOpenDuty != null && !widget.member.isPersonal)
          OutlinedButton.icon(
            onPressed: widget.onOpenDuty,
            icon: const Icon(Icons.schedule),
            label: const Text('Horarios, faltas y coberturas'),
          ),
        Wrap(
          spacing: 8,
          children: [
            for (final e in {
              'appointments': 'Agenda / estética',
              'services': 'Servicios',
              if (!widget.member.isPersonal) 'tasks': 'Pendientes',
              if (!widget.member.isPersonal) 'messages': 'Mensajes',
              'suppliers': 'Distribuidores',
              'acts': 'Desempeño',
            }.entries)
              if (!model.explicitPermissions || model.sectionAllowed(e.key))
                ChoiceChip(
                  label: Text(e.value),
                  selected: section == e.key,
                  onSelected: (_) => setState(() => section = e.key),
                ),
            TextButton(
              onPressed: model.busy
                  ? null
                  : () => form(
                      'Mi nombre visible en la clínica',
                      'display_name',
                      const [
                        RxField(
                          'name',
                          'Nombre que verán los integrantes de esta clínica',
                          required: true,
                        ),
                      ],
                      initial: {
                        'name':
                            model
                                .rows('people')
                                .where(
                                  (p) => p['user_id'] == widget.member.userId,
                                )
                                .firstOrNull?['display_name'] ??
                            '',
                      },
                    ),
              child: const Text('Mi nombre en el equipo'),
            ),
            if (!model.explicitPermissions)
              TextButton(
                onPressed: model.busy ? null : medical,
                child: const Text('Ficha médica privada'),
              ),
            IconButton(
              onPressed: model.busy ? null : model.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (model.busy) const LinearProgressIndicator(),
        if (model.error != null)
          Text(
            model.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (activeSection == 'blocked')
          const Text('No tienes permiso para esta sección.'),
        if (activeSection == 'appointments') ...[
          FilledButton(
            onPressed:
                model.busy ||
                    (model.explicitPermissions &&
                        !model.allowed('appointment.manage'))
                ? null
                : newAppointment,
            child: const Text('Agendar cita'),
          ),
          ExpansionTile(
            title: const Text('Calendario'),
            children: [
              CalendarDatePicker(
                initialDate: calendarDay ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 90)),
                lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                onDateChanged: (d) => setState(() => calendarDay = d),
              ),
              TextButton(
                onPressed: () => setState(() => calendarDay = null),
                child: const Text('Mostrar todas las citas'),
              ),
            ],
          ),
          for (final a in model.rows('appointments').where((a) {
            if (calendarDay == null) return true;
            final d = DateTime.parse(a['starts_at'] as String).toLocal();
            return DateUtils.isSameDay(d, calendarDay);
          }))
            Card(
              child: ListTile(
                onTap:
                    a['patient_id'] != null &&
                        widget.onOpenPatient != null &&
                        (!model.explicitPermissions ||
                            model.allowed('patient.read'))
                    ? () => widget.onOpenPatient!(a['patient_id'] as String)
                    : null,
                title: Text(
                  '${a['patient_name']} · ${a['kind']}${a['patient_id'] == null ? '' : ' · Vinculado al expediente'}',
                ),
                subtitle: Text(
                  '${DateTime.parse(a['starts_at'] as String).toLocal()} · ${appointmentStateLabel(a['state'] as String)}\n${a['notes'] ?? ''}',
                ),
                trailing: PopupMenuButton<String>(
                  enabled:
                      !model.explicitPermissions ||
                      model.allowed('appointment.manage'),
                  onSelected: (state) => state == 'reprogramar'
                      ? form(
                          'Reprogramar cita',
                          'appointment_reschedule',
                          const [
                            RxField(
                              'starts_at',
                              'Nuevo inicio',
                              type: 'local_instant',
                              required: true,
                            ),
                            RxField(
                              'ends_at',
                              'Nuevo fin',
                              type: 'local_instant',
                              required: true,
                            ),
                            RxField(
                              'reason',
                              'Motivo del cambio',
                              required: true,
                            ),
                          ],
                          initial: {
                            'id': a['id'],
                            'version': a['version'],
                            'starts_at': a['starts_at'],
                            'ends_at': a['ends_at'],
                          },
                        )
                      : form(
                          'Actualizar cita',
                          'appointment_state',
                          state == 'cancelado'
                              ? const [
                                  RxField(
                                    'reason',
                                    'Motivo de cancelación',
                                    required: true,
                                  ),
                                ]
                              : const [],
                          initial: {
                            'id': a['id'],
                            'version': a['version'],
                            'state': state,
                          },
                        ),
                  itemBuilder: (_) => [
                    if (a['state'] == 'agendado')
                      const PopupMenuItem(
                        value: 'reprogramar',
                        child: Text('Reprogramar'),
                      ),
                    for (final s in switch (a['state']) {
                      'agendado' => ['en_atencion', 'cancelado'],
                      'en_atencion' => ['listo', 'cancelado'],
                      'listo' => ['entregado'],
                      _ => <String>[],
                    })
                      PopupMenuItem(
                        value: s,
                        child: Text(appointmentStateLabel(s)),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (activeSection == 'services') ...[
          if (admin)
            FilledButton(
              onPressed: () => service(),
              child: const Text('Nuevo servicio'),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Organiza los servicios que ofrece tu clínica. '
                'Cada clínica define sus nombres y precios.'),
          ),
          for (final category in serviceCategories.entries)
            ExpansionTile(
              key: ValueKey('service-category-${category.key}'),
              title: Text(category.value),
              subtitle: Text(
                '${model.rows('services').where((s) => serviceCategory(s) == category.key).length} servicios registrados',
              ),
              children: [
                if (admin)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final example in serviceExamples[category.key]!)
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: Text(example),
                          onPressed: () => service(null, category.key, example),
                        ),
                    ],
                  ),
                if (admin)
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Otro servicio / subcategoría personalizada'),
                    onPressed: () => service(null, category.key),
                  ),
                for (final sub in <String>{
                  ...?serviceSubcategories[category.key],
                  for (final row in model.rows('services')
                      .where((s) => serviceCategory(s) == category.key))
                    serviceSubcategory(row),
                })
                  ExpansionTile(
                    title: Text(sub.isEmpty ? 'Sin subcategoría' : sub),
                    children: [
                      if (admin)
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar servicio aquí'),
                          onPressed: () => service(null, category.key, '', sub),
                        ),
                      for (final row in model.rows('services').where((s) =>
                          serviceCategory(s) == category.key &&
                          serviceSubcategory(s) == sub))
                        ListTile(
                          title: Text('${row['name']} · \$${row['price']}'),
                          subtitle: Text('Comisión: ${row['commission_kind']} '
                              '${row['commission_value']} · versión ${row['version']}'),
                          trailing: admin
                              ? IconButton(
                                  tooltip: 'Editar servicio',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => service(row),
                                )
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          FilledButton(
            onPressed: () =>
                form('Registrar servicio realizado', 'service_act', [
                  RxField(
                    'service_id',
                    'Servicio',
                    type: 'select',
                    options: {
                      for (final s in model.rows('services'))
                        s['id'] as String: s['name'] as String,
                    },
                    required: true,
                  ),
                  RxField(
                    'professional_id',
                    'Quién realizó el servicio',
                    type: 'select',
                    options: admin || widget.member.role == ClinicRole.recepcion
                        ? people
                        : {widget.member.userId: widget.member.role.label},
                    required: true,
                  ),
                  RxField(
                    'appointment_id',
                    'Cita opcional',
                    type: 'select',
                    options: {
                      for (final a in model.rows('appointments'))
                        a['id'] as String: a['patient_name'] as String,
                    },
                  ),
                ]),
            child: const Text('Registrar servicio realizado'),
          ),
        ],
        if (activeSection == 'tasks') ...[
          FilledButton(
            onPressed: () => form('Nuevo pendiente', 'task', [
              const RxField('title', 'Pendiente', required: true),
              RxField(
                'assigned_to',
                'Asignado a (vacío: todos)',
                type: 'select',
                options: people,
              ),
              const RxField(
                'priority',
                'Prioridad',
                type: 'select',
                options: {
                  'urgente': 'Urgente',
                  'media': 'Media',
                  'baja': 'Baja',
                },
                required: true,
              ),
            ]),
            child: const Text('Crear pendiente'),
          ),
          DropdownButton<String>(
            value: filter,
            items: [
              for (final f in ['pendientes', 'completadas', 'todas'])
                DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) => setState(() => filter = v!),
          ),
          for (final t
              in model
                  .rows('tasks')
                  .where(
                    (t) =>
                        filter == 'todas' ||
                        (filter == 'pendientes') == (t['completed_at'] == null),
                  ))
            ListTile(
              title: Text('${t['title']} · ${t['priority']}'),
              subtitle: Text(
                t['assigned_to'] == null
                    ? 'Todos'
                    : person(t['assigned_to'] as String),
              ),
              trailing: t['completed_at'] == null
                  ? IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () => form(
                        'Completar pendiente',
                        'task_complete',
                        const [],
                        initial: {'id': t['id']},
                      ),
                    )
                  : const Icon(Icons.done_all),
            ),
        ],
        if (activeSection == 'messages') ...[
          FilledButton(
            onPressed: () => form('Mensaje al equipo', 'message', const [
              RxField(
                'category',
                'Categoría',
                type: 'select',
                options: {
                  'general': 'General',
                  'urgente': 'Urgente',
                  'aviso': 'Aviso',
                  'turno': 'Turno',
                },
                required: true,
              ),
              RxField(
                'body',
                'Mensaje (sin datos sensibles de pacientes o personal)',
                required: true,
              ),
            ]),
            child: const Text('Escribir mensaje'),
          ),
          for (final m in model.rows('messages'))
            ListTile(
              title: Text('${m['category']} · ${m['body']}'),
              subtitle: Text(
                '${person(m['author_id'] as String)} · ${m['created_at']}',
              ),
            ),
        ],
        if (activeSection == 'suppliers') ...[
          if (admin || widget.member.role == ClinicRole.recepcion)
            FilledButton(
              onPressed: () => form('Distribuidor', 'supplier', const [
                RxField('name', 'Nombre', required: true),
                RxField('phone', 'Teléfono con código de país'),
                RxField('notes', 'Notas'),
              ]),
              child: const Text('Agregar distribuidor'),
            ),
          for (final s in model.rows('suppliers'))
            ListTile(
              title: Text('${s['name']}'),
              subtitle: Text('${s['phone']} · ${s['notes']}'),
              trailing: PopupMenuButton<String>(
                itemBuilder: (_) => [
                  for (final x in ['WhatsApp', 'Llamar', 'SMS'])
                    PopupMenuItem(value: x, child: Text(x)),
                ],
                onSelected: (x) async {
                  final p = (s['phone'] as String).replaceAll(
                    RegExp(r'[^0-9+]'),
                    '',
                  );
                  if (p.isEmpty) return;
                  final uri = x == 'WhatsApp'
                      ? Uri.https('wa.me', p.replaceAll('+', ''))
                      : Uri(scheme: x == 'Llamar' ? 'tel' : 'sms', path: p);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ),
        ],
        if (activeSection == 'acts') ...[
          TextButton(
            onPressed: exportPerformance,
            child: const Text('Exportar servicios y comisiones CSV'),
          ),
          for (final e in performance.entries)
            ListTile(
              title: Text(person(e.key)),
              subtitle: Text(
                'Comisión registrada: ${e.value[0].display} · cobrada: ${e.value[1].display}',
              ),
            ),
          const Text(
            'Servicios realizados y comisión congelada. “Cobrado” exige venta vigente en caja; las devoluciones se muestran por separado en inventario.',
          ),
          for (final a in model.rows('acts'))
            ListTile(
              title: Text('${a['name']} · \$${a['price']}'),
              subtitle: Text(
                '${person(a['professional_id'] as String)} · comisión \$${a['commission']} · ${a['paid'] == true ? 'Cobrado' : 'Pendiente de cobro'}',
              ),
            ),
        ],
        if (!model.busy && model.rows(section).isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin registros visibles en esta sección.'),
          ),
      ],
    ),
  );

  Map<String, List<Money>> get performance {
    final sums = <String, List<Money>>{};
    for (final a in model.rows('acts')) {
      final key = a['professional_id'] as String;
      final v = sums.putIfAbsent(
        key,
        () => [Money(BigInt.zero), Money(BigInt.zero)],
      );
      final commission = Money.parse(a['commission'] as String);
      v[0] = v[0] + commission;
      if (a['paid'] == true) v[1] = v[1] + commission;
    }
    return sums;
  }

  Future<void> exportPerformance() async {
    try {
      final csv = BackupArchive.tableCsv([
        for (final act in model.rows('acts'))
          {
            ...act,
            'professional_name': person(act['professional_id'] as String),
          },
      ]);
      await FilePicker.saveFile(
        fileName: 'servicios-comisiones.csv',
        bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    }
  }

  Future<void> service([
    Map<String, dynamic>? s,
    String category = 'otro',
    String name = '',
    String subcategory = '',
  ]) => form(s == null ? 'Nuevo servicio' : 'Editar servicio', 'service', const [
        RxField('category', 'Categoría del servicio', type: 'select',
            options: serviceCategories, required: true),
        RxField('name', 'Nombre del servicio / tipo de cirugía', required: true),
        RxField('subcategory', 'Subcategoría (puedes escribir una nueva)'),
        RxField('price', 'Precio MXN', required: true),
        RxField(
          'commission_kind',
          'Tipo de comisión',
          type: 'select',
          options: {'porcentaje': 'Porcentaje', 'bono': 'Bono fijo MXN'},
          required: true,
        ),
        RxField('commission_value', 'Valor de comisión', required: true),
      ], initial: s == null
          ? {'category': category, 'subcategory': subcategory, 'name': name,
             'commission_kind': 'bono', 'commission_value': '0'}
          : {...s, 'category': serviceCategory(s)});
}

String appointmentStateLabel(String state) => switch (state) {
  'agendado' => 'Agendada',
  'en_atencion' => 'En atención',
  'listo' => 'Lista para entrega',
  'entregado' => 'Entregada',
  'cancelado' => 'Cancelada',
  _ => state,
};

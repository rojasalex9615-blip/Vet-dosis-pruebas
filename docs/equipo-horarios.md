# Equipo: horarios, permisos de falta y coberturas

## Alcance

En **Equipo y avisos → Horarios, faltas y coberturas** y en el perfil de la
clínica, cada integrante conectado captura, corrige o cancela sus turnos.
El administrador puede hacerlo por cualquier integrante y autorizar faltas
con motivo y sustituto opcional. Registrar una falta constituye la autorización
del administrador; no se añade un flujo de solicitudes pendientes.

- Intervalos explícitos con fecha inicial/final, hora y zona IANA. Admiten noche
  y cambio de fecha; turnos de hasta 24 horas y faltas de hasta 90 días.
  No hay recurrencia semanal implícita ni inferencia desde el checado.
- Horas inexistentes o ambiguas por cambio de horario se rechazan. Los límites
  incluyen el inicio y excluyen el final. La lista indica sus horas en UTC.
- Las ediciones crean otra versión y cancelan la anterior, con motivo, autor y
  fecha. No se reescriben originales. Se rechazan ediciones de intervalos
  terminados y solapamientos del mismo tipo para la misma persona.
- Faltas prevalecen sobre turnos y coberturas. La cobertura permite estar en
  turno durante el intervalo autorizado aunque no haya un turno propio.
  Si quien cubre también falta, queda fuera. No hay cadenas automáticas de suplencia.
- Cada horario y cobertura queda ligado a la instancia de membresía. Una baja
  y nueva invitación no recuperan las asignaciones anteriores.
- Motivos solo visibles para la persona afectada y administración. Quien cubre
  puede ver su asignación sin conocer el motivo de la falta ajena. No se copian
  motivos al registro general de auditoría. Evitar diagnósticos en este campo.

## Reparto de avisos

`14H_team_duty.sql` añade una variante de la generación de avisos de 14G:

1. Filtra personas con membresía, permisos actuales y turno/cobertura vigente.
2. Prefiere al encargado/MVZ de la ruta configurada o a su cobertura elegida.
3. Si ninguno está disponible, asigna a los demás integrantes habilitados en
   turno para esa etapa. Si no hay ninguno, no envía a alguien fuera de turno.
4. Para escalar al MVZ conserva la verificación profesional y designación de
   responsable vigente. Cubrir una falta **no concede autoridad clínica**.
5. Conserva avisos y respuestas anteriores, y deduplica por tarea, etapa,
   destinatario e instancia de membresía. La respuesta sigue sin confirmar el cuidado.

La pantalla avisa al administrador si no hay personal habilitado o MVZ
responsable en turno. Las advertencias requieren abrir/actualizar la pantalla;
no son una escalación externa adicional.

## Integración pendiente: teléfono y WhatsApp

Los canales solicitados son **notificación en teléfono y WhatsApp**. Esta entrega
implementa horarios y selección de destinatarios; **no implementa todavía sus
transportes externos**. Se consulta Meta Cloud API para WhatsApp y FCM para push.
FCM ampliaría el acuerdo anterior de usar Firebase solo para distribución;
la elección del proveedor sigue pendiente de respuesta.

La migración deja `private.hospital_automation_runtime.duty_routing_enabled=false`.
No activar ese indicador hasta integrar y probar ambos transportes. Mientras
está apagado, conserva el comportamiento previo de 14G y las alarmas locales.
La captura de horarios funciona independientemente de esa activación.

Al activarlo, el snapshot anuncia `duty_routing_version=1`; el cliente nuevo
retira sus alarmas locales al actualizar la hoja. Esto evita programar alarmas
que después no podrían revocarse mientras el dispositivo está desconectado.
Un teléfono antiguo o desconectado puede conservar alarmas anteriores: la
puesta en marcha debe actualizar todos los dispositivos y comprobar su
cancelación. No se promete silencio remoto en esos dispositivos.

El futuro envío deberá volver a comprobar turno, ausencia, permisos, membresía,
respuesta, estado de tarea y alta **antes de cada intento**, además de verificar
el destino y consentimiento, gestionar reintentos y no enviar datos clínicos
por la pantalla bloqueada o WhatsApp. Aceptación del proveedor no acredita entrega.

## Instalación y comprobación

Candidato local `supabase/proposed/14H_team_duty.sql`, después de las dependencias
reales de 14G. No asumir que otros archivos con igual número de otra rama son
compatibles. No se aplicó a Supabase remoto; conexión reservada para el final.

Pruebas sintéticas:

```bash
flutter test --no-pub test/team_duty_test.dart
HOSPITAL_TEST_DUTY=1 bash supabase/tests/run_hospital_automation.sh
```

El segundo comando requiere Docker y usa PostgreSQL 17 aislado: permisos,
idempotencia, ausencias, privacidad, coberturas, generación de avisos,
remembresía y concurrencia; incluye las regresiones hospitalarias previas.
Pruebas reales de cuentas, APK, app cerrada, reinicio y proveedores pendientes.

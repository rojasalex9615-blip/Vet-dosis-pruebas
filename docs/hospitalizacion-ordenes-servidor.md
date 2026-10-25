# Hospitalización: órdenes diarias y escalación (candidato 14G)

Implementación integrada en `main` y esquema 14G instalado en Supabase Pruebas.
`pg_cron` 1.6.4 y el trabajo `vetdosis-hospital-minute` están instalados.
El generador y el reparto por turnos siguen desactivados (`enabled=false`,
`duty_routing_enabled=false`). El canal externo para recibir avisos con la app
cerrada queda por elegir, configurar y comprobar. Una fila en la bandeja no
acredita entrega al teléfono.

## Recorrido

Hospitalización → **Órdenes diarias de este paciente** → **Crear orden diaria en
servidor**. Para consultar todo el historial o configurar responsables:
**Órdenes diarias y avisos del servidor**.

Se captura tipo de procedimiento, nombre e indicación profesional completa,
primera/última fecha, zona IANA, horas diarias y minutos sin respuesta para escalar.
Todos los campos se revisan expresamente; no hay indicaciones, dosis, porciones,
intervalos ni destinatarios sugeridos. Alimentación y dispositivos pueden usar
estas revisiones; la medicación conserva su flujo estructurado de receta/aplicación.

La confirmación existente y el resultado del cuidado siguen usando las mismas
tareas tipadas. El generador no realiza ni interpreta actos clínicos.

## Generación y vigencia

Cada orden es inmutable y conserva autor, permisos originales y versión. El
servidor genera tareas de hoy y mañana según la **zona declarada en la orden**,
con una clave única por orden/instante. El límite continúa siendo 31 fechas y
200 tareas totales por orden. Al terminar no se renueva automáticamente.

Al autorizar, todos los horarios de la vigencia deben ser futuros. Las fechas
inválidas, tiempos duplicados y horas inexistentes o ambiguas por cambio estacional
se rechazan. Se comprueba todo el periodo antes de aceptar la orden; no se usa la
zona del teléfono o la sesión SQL para decidir sus instantes.

Si el proceso se interrumpe, al volver genera los horarios autorizados omitidos
como tareas pendientes, incluidos los vencidos. No marca cuidados atrasados como
realizados ni los elimina. No amplía la vigencia para compensar la interrupción.

**Crear nueva versión** exige capturar la indicación completa y un motivo. Detiene
los horarios futuros pendientes de la anterior y conserva originales, realizados
y vencidos para resolución explícita. **Detener horarios futuros** hace lo mismo
sin crear una versión nueva. Ambas operaciones tienen recibos idempotentes.
La programación finita anterior desde el teléfono sigue disponible sin cambiar.

El alta usa el contrato previo de revisión/cancelación de tareas. El generador no
crea tareas para una estancia de alta y registra el fin de la orden. La pérdida
de membresía, permiso original, habilitación profesional o tipo activo detiene
la generación y cancela futuros pendientes de esa orden. Un permiso nuevo no la
reactiva: requiere una nueva orden revisada. Esto aplica solo a órdenes 14G;
no cambia retrospectivamente las órdenes explícitas anteriores de 13E.

## Avisos y respuestas

Configurar una ruta requiere `hospital.read` y el nuevo permiso explícito
`hospital.automation.manage`. No se conceden permisos al instalar.

Se eligen dos integrantes distintos:

- Encargado: membresía actual, `hospital.read` y `hospital.report` vigentes.
- Escalación: los mismos permisos más MVZ responsable designado, aceptado,
  profesional verificado y vigente. El nombre del puesto no concede autoridad.

Cuando una tarea pendiente vence, el servidor registra el primer aviso. Si no hay
respuesta al vencer el plazo de escalación de la tarea, registra otro para el MVZ.
Se respetan posposiciones vigentes; al terminar la posposición se evalúa el retraso
original. Las tareas terminadas/canceladas o estancias de alta no producen avisos
nuevos. La ruta se evalúa por clínica y no depende del teléfono ni del turno nocturno.

**Confirmar que recibí el aviso** guarda persona, hora del servidor y nota. Solo el
destinatario con membresía y permisos actuales puede responder. Una respuesta que
se confirma antes de la escalación evita ese siguiente aviso. No confirma el
cuidado, cancela la tarea ni silencia su alarma local. Si la escalación ya existe,
se conserva como antecedente; no se borra al responder después.

Los avisos se deduplican por tarea, etapa, persona e instancia de membresía, para
que un cambio de responsables pueda llegar al sustituto. Si el encargado pierde
acceso, eso no impide escalar a un MVZ que siga autorizado. Si el MVZ pierde acceso,
no se sustituye por otra persona de memoria: hay que corregir la ruta. La bandeja
señala destinatarios sin autorización actual y conserva el historial de respuestas.

Los reintentos idénticos conservan operación y contenido; cambiar el contenido
usa otra operación. Una revocación impide usar un recibo anterior para eludir los
permisos. No hay guardado clínico offline ni credenciales de servicio en la app.

## Instalación revisada al final

1. Revisar la cadena de permisos/adaptaciones hasta 13G y los snapshots 14D/14F.
2. `supabase/proposed/14G_hospital_automation.sql` ya está instalado en
   Supabase **Pruebas**. La migración exigió beta cerrada/permisos globales
   inactivos y dejó el generador **desactivado**. No asignó personas ni activó
   el corte de permisos.
3. Asignar permisos y verificar las dos personas de la ruta con cuentas reales.
4. `pg_cron` y el trabajo por minuto ya están instalados en Supabase Pruebas.
   Se registró el trabajo sin activar el generador. Para activarlo después de
   configurar rutas y canales, revisar el candidato
   `supabase/operations/hospital_scheduler.sql`. La activación no la puede
   realizar un cliente autenticado ni service_role.
5. Revisar `cron.job`, `cron.job_run_details`, la última ejecución mostrada y la
   auditoría `hospital_automation_failed`. La fecha de última ejecución indica
   intento, no prueba de que todas las clínicas terminaron bien.
6. Elegir/configurar el transporte externo y verificar recepción real con app
   cerrada, revocación, errores/reintentos del proveedor y permisos del teléfono.

Pausa operativa: `update private.hospital_automation_runtime set enabled=false;`.
Un trabajo ya ejecutándose puede terminar; el siguiente no genera tareas. Para
retirar la programación: `select cron.unschedule('vetdosis-hospital-minute');`.
Pausar el generador no cancela las tareas clínicas existentes.

Las funciones del trabajador son privadas y solo las ejecuta su propietario en
servidor. Los errores por clínica revierten su lote y se auditan con SQLSTATE;
no bloquean el intento de otras clínicas ni se anuncian como tareas generadas.
Los datos de pacientes/indicaciones no se envían a proveedores en esta entrega.

## Validación local

```sh
flutter analyze --no-pub
flutter test --no-pub test/hospital_automation_test.dart
bash supabase/tests/run_hospital_automation.sh
```

Para comprobar el programador real en una base desechable, con Docker disponible:

```sh
bash supabase/tests/build_hospital_cron_image.sh
HOSPITAL_TEST_IMAGE=vetdosis-postgres17-cron:test HOSPITAL_TEST_CRON=1 \
  bash supabase/tests/run_hospital_automation.sh
```

La imagen local compila `pg_cron` 1.6.7 desde fuente oficial con hash fijado,
contra PostgreSQL 17. No contiene claves o conexiones reales. La prueba comprueba
la programación por minuto del script de operador y acelera ese mismo trabajo a
un segundo para verificar generación autónoma y pausa; destruye la base al salir.

Flutter cubre captura a 320 dp, revisión obligatoria, reintentos, alcance,
respuestas separadas de realización, nuevas versiones, contratos desconocidos y
navegación global/por ingreso. PostgreSQL cubre cantidades de tareas, instantes,
DST, recuperación tras interrupción, permisos, historia, revocación, alta,
concurrencia del generador/cancelación/respuesta y regresiones de 13G/14D/14F.
No acredita el despliegue, la entrega externa o una alarma en teléfono real.

### Horarios y cobertura del equipo (24 de octubre de 2026)

[Horarios propios/admin, faltas y cobertura elegida](equipo-horarios.md): implementación
local con historial y permisos. El reparto de avisos por turno está preparado
y apagado hasta integrar teléfono/WhatsApp y retirar las alarmas locales
anteriores de cada dispositivo. No hay despliegue remoto ni entrega externa
certificada en este bloque.

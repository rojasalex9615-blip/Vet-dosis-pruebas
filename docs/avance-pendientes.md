# Implementación de pendientes

## Corte actual — 24 de octubre de 2026

Las casillas siguientes significan **código implementado y validación local
completada**. La integración a `main` y la instalación de 14D–14I en
Supabase **Pruebas** se completaron después de este corte; las comprobaciones
con cuentas/teléfonos reales siguen pendientes. La automatización y el reparto
por turnos permanecen desactivados.

### Realizado en esta entrega

- [x] **Alimentación, catéter y equipo:** programación finita por fechas y horarios,
  con porciones/instrucciones capturadas y permisos por procedimiento.
  [Alcance y límites](hospitalizacion-cuidados-diarios.md).
- [x] **Peso diario hospitalizado:** registro vinculado al caso, aviso de peso
  pendiente y elección explícita de un peso registrado para el cálculo.
  [Alcance y límites](hospitalizacion-peso-diario.md).
- [x] **Aislamiento y limpieza:** bandera de estancia/jaula, registro de acceso,
  checklist capturado por la clínica, historial y protección contra reutilizar
  una jaula pendiente de limpieza. [Alcance y límites](hospitalizacion-aislamiento.md).
- [x] **Pruebas rápidas:** captura manual C/T, resultado, interpretación profesional
  opcional y foto privada, vinculados al caso/paciente; autoría y correcciones
  que conservan el original. [Alcance y límites](pruebas-rapidas.md).

- [x] **Resultados de cuidados:** cantidad ofrecida/consumida y hallazgos manuales,
  confirmación atómica, autoría y correcciones que conservan el original.
  [Alcance y límites](hospitalizacion-resultados-cuidados.md).

- [x] **Órdenes diarias de servidor:** vigencia, zona IANA, versiones y generación
  sin duplicados; recuperación tras interrupción y pausa, probadas con `pg_cron` local.
  [Alcance y límites](hospitalizacion-ordenes-servidor.md).
- [x] **Escalación en bandeja y respuestas:** encargado/MVZ configurados por clínica,
  aviso por falta de respuesta e historial de quién respondió. Recibir el aviso no
  confirma el cuidado. **La entrega externa sigue pendiente**.
  [Alcance y límites](hospitalizacion-ordenes-servidor.md).

- [x] **Equipo: horarios, faltas y coberturas:** captura propia/admin, autorización
  de faltas con motivo, sustituto elegido, historial y selección de destinatarios
  en turno sin ampliar permisos clínicos. Activación del reparto pendiente de
  transportes. [Alcance y límites](equipo-horarios.md).

- [x] **Consulta de hospitalizaciones dadas de alta:** búsqueda por paciente,
  páginas de estancias e indicaciones, motivo/autores del alta y movimientos de
  jaula; permisos de lectura y consulta sin nuevas aplicaciones ni alarmas.
  [Alcance y límites](hospitalizacion-historial-altas.md).

### Commits de implementación

| Bloque | Commit |
|---|---|
| Cuidados, peso y aislamiento hospitalario | [343addb](https://github.com/rojasalex9615-blip/Vetdosis-pruebAS/commit/343addb8c16b45774867707aa57d207c317ea4b1) |
| Pruebas rápidas por caso y fotos privadas | [6857d0e](https://github.com/rojasalex9615-blip/Vetdosis-pruebAS/commit/6857d0e0a6953db7abe3e212be4698fbc9689cce) |
| Resultados y consumo de cuidados hospitalarios | [e4a97fd](https://github.com/rojasalex9615-blip/Vetdosis-pruebAS/commit/e4a97fdf9c0c47b2f42c58fcb861f23fc867bc48) |
| Órdenes diarias y escalación en bandeja / pg_cron local | [b3bf50a](https://github.com/rojasalex9615-blip/Vetdosis-pruebAS/commit/b3bf50a83ca169c7719f7c205a76fa517c908b7c) |
| Equipo: horarios, permisos de falta y cobertura por turno | [a69f51b](https://github.com/rojasalex9615-blip/Vetdosis-pruebAS/commit/a69f51bf74a39452ad28711923963f8a978d0fd4) |
| Historial de altas hospitalarias e indicaciones | [29ddf3e](https://github.com/rojasalex9615-blip/Vetdosis-pruebAS/commit/29ddf3ef9123fa06b3a11d4098b1a2252bf5696b) |

Rama de entrega: `coderabbit/modo-revision-catalogos/ff72dd6b`.
Estos commits no incorporan automáticamente los cambios a `main`.

### Validación de esta entrega

- Análisis Flutter sin incidencias.
- Suite completa: **435 pruebas aprobadas y 1 omitida** en UTC. La omitida de
  cambio de horario conserva su aprobación anterior bajo `America/New_York`
  para los mismos archivos y entorno; no se afirma una nueva ejecución en esa zona.
- PostgreSQL 17: permisos, alcance entre clínicas/casos, reintentos, correcciones
  y políticas de fotos; aislamiento/limpieza, resultados atómicos de cuidados y
  concurrencia de confirmaciones/jaulas/revocación, generación/cancelación/respuesta.
- Programador real local `pg_cron` 1.6.7: generación autónoma y pausa correctas.
- Comprobación final del formulario de horarios: **5 pruebas aprobadas**,
  incluida la conservación de zona local y sustituto al editar. El conjunto
  hospitalario afectado aprobó otras **25 pruebas** antes de ese último ajuste
  de formulario; los resultados no se suman como una nueva suite completa.
- Horarios: permisos propios/admin, privacidad de motivos, ausencia/cobertura,
  historial, límites de intervalo, remembresía y exclusión de alarmas locales
  en el modo por turnos.
- Sin cambios de dependencias ni datos clínicos/normativos precargados.

### Validación del historial de altas

- Análisis Flutter sin incidencias.
- Pruebas de regresión de hospitalización/horarios: **63 aprobadas**; comprobación
  final del historial: **8 aprobadas**, con búsqueda/paginación, respuestas tardías,
  sesión, contrato/RPC y 320 dp con texto ampliado. Los resultados se solapan.
- PostgreSQL 17: altas separadas por clínica, permiso revocado, búsqueda literal,
  páginas con fechas iguales y consulta sin escrituras; también pasan las
  regresiones previas y concurrencia de hospitalización/horarios.
- La suite completa anterior sigue como evidencia para archivos no afectados;
  este bloque se validó con las pruebas enfocadas de sus consumidores.

### Pendiente de estos bloques

- [x] Integrar la rama a `main` y pasar sus controles de CI (PR #23).
- [x] Instalar 14D–14I en Supabase **Pruebas**, sin activar el programador.
- [ ] Verificar Auth con dos sesiones y clínicas, revocación y expiración.
- [ ] Subida/descarga real de Storage y cámara/galería en APK firmado.
- [ ] Alarmas en teléfono con app cerrada y tras reinicio.
- [ ] Instalar/activar y comprobar `pg_cron` y órdenes/avisos 14G en el entorno
  remoto de pruebas, con sus permisos, destinatarios y monitoreo. 14G está
  instalado, pero su bandera `enabled` sigue en `false` y `pg_cron` no está instalado.
- [ ] Integrar los canales elegidos: **teléfono y WhatsApp**. Confirmar proveedor
  (FCM ampliaría Firebase más allá de distribución), destinos/consentimiento,
  entrega con app cerrada, errores/reintentos y revocación; activar reparto
  por turnos solo tras comprobarlo y retirar alarmas antiguas de los dispositivos.
- [ ] Limpieza de fotos huérfanas con retención acordada y recuperación ensayada.

Los catálogos/fuentes oficiales, clasificación normativa y demás puntos del
handoff conservan sus pendientes. Este corte no los marca como completados.
Las secciones fechadas anteriores se conservan como historial de cada entrega.


## Bloque 1: acceso y protección de captura (8 de octubre de 2026)

Implementado localmente:
- Solicitud de recuperación de contraseña por correo, con respuesta neutral que no confirma si una cuenta existe.
- Supabase procesa el enlace de recuperación; la app muestra nueva contraseña y confirmación, y exige una sesión de recuperación para actualizarla. Cancelar cierra sesión. Las membresías y roles no cambian.
- Aviso al retroceder desde `RxEntryScreen` con cambios: seguir editando o salir sin guardar. Cubre los formularios que reutilizan este componente, incluyendo sus indicaciones y firmas; no todos los editores de la app.
- Durante el envío se bloquea retroceder. Un fallo conserva la captura; un guardado exitoso permite cerrar sin aviso.

No se guarda un borrador clínico sin cifrar en el dispositivo. El aviso protege la navegación dentro de la app; no puede impedir que el sistema cierre el proceso o que el usuario cierre la pestaña. Recuperar borradores y extender el aviso a los demás editores siguen pendientes.

### Integración final

En Supabase Auth, configurar URL del sitio, redirecciones web y `com.vetdosis.pro://login-callback/`, correo transaccional y límites de envío. Probar enlaces reales, expiración, reuso, correo y recepción de enlaces en cada plataforma. No se envió correo real durante estas pruebas. La configuración y las verificaciones del proveedor se harán al final; solicitar una clave o configuración adicional ahora no es necesario.

## Siguientes bloques de código

1. Extender protección de captura a los editores clínicos y de documentos, con revisión de privacidad para recuperación de borradores.
2. Gestión del equipo e invitaciones: listado, revocación y cambios de rol con controles del servidor y protección del último administrador.
3. Identidades legibles del equipo y vinculación de citas a pacientes.
4. Flujos pendientes de inventario, devoluciones y frascos, conservando movimientos y correcciones anexadas.
5. Restauración verificable de respaldos y mejoras de navegación, paginación y accesibilidad.
6. Ciclo de suscripciones y soporte: cancelaciones, impagos, adjuntos y retención, antes de activar cobros.

Cada bloque debe registrar alcance real y pruebas. Esta lista no afirma que los bloques restantes estén implementados.

## Información y servicios que se completan al final

- Catálogos clínicos con fuentes y revisión profesional; clasificación normativa y textos/aviso de privacidad aprobados por la clínica.
- Credenciales y cuentas elegidas de IA, pagos, Google/Drive y proveedores opcionales de mensajería.
- Configuración de producción, dominio, cuentas de publicación, identidad visual y pruebas con teléfonos reales.
- Validación de costos y condiciones comerciales.

El código preparatorio y sus pruebas locales pueden avanzar antes de estos aportes. Algunas comprobaciones finales requieren también nuestro trabajo de despliegue y pruebas, además de los datos que aporte la usuaria.

## Verificación del bloque 1

`flutter analyze`: sin incidencias. `flutter test`: 138 pruebas aprobadas, incluyendo recuperación con sesión válida/confirmación y conservar o descartar cambios al retroceder. No se cambiaron tablas ni se aplicaron migraciones remotas en este bloque.

## Bloque 2: equipo e invitaciones

Implementado localmente para el esquema Supabase existente:
- En «Mi cuenta y clínicas», el administrador conectado de una clínica puede abrir «Administrar equipo e invitaciones».
- Lista de integrantes identificados por correo, cambio de rol y baja con confirmación. La baja elimina la membresía, no la cuenta ni sus registros históricos.
- Invitaciones con estado pendiente, aceptada, revocada o vencida; revocación de pendientes mediante el RPC existente. Los códigos secretos y hashes no se devuelven en el listado.
- El servidor autoriza cada operación por clínica y administrador; conserva la protección existente del último administrador y registra las bajas en la bitácora. La UI refresca las membresías después de cambios.
- Ante un fallo de lectura se borra el listado. Si cambian los permisos, deja de mostrarse el contenido de administración. La consulta no muestra fichas médicas del personal.
- Un rol de acceso no habilita automáticamente a un profesional para actos clínicos reservados.

Integración final: aplicar `supabase/adaptations/existing_team_management.sql` una vez, después de M2 y antes de utilizar esta pantalla. Es aditivo: dos RPC nuevos, sin tablas nuevas ni reemplazo del esquema. La modalidad de instalación nueva aún no expone esta pantalla; se trabaja sobre la base existente aportada por la usuaria. No se modificó la base remota.

Verificación: 140 pruebas Flutter aprobadas; pruebas SQL locales de M2 y equipo aprobadas (permisos, último administrador, baja y bitácora). Pruebas enfocadas de pantalla y autenticación aprobadas tras el ajuste de disponibilidad para el esquema existente. Los nombres legibles en otras pantallas y el listado paginado de equipos muy grandes continúan pendientes.

## Bloque 3: agenda, nombres visibles e historial al dar de baja

Implementado localmente:
- Búsqueda de pacientes por nombre dentro de la clínica (máximo 50 coincidencias por búsqueda). El selector solo recibe ID, nombre y especie; no recibe propietarios ni notas clínicas. Un resultado tardío se descarta si cambia la búsqueda.
- Cita vinculada a un paciente existente. El servidor toma el nombre/especie del expediente; no confía en los valores enviados desde el dispositivo. Mantiene la opción de cita sin expediente, sin crear un paciente automáticamente. El estilista continúa sin acceder al buscador de expedientes.
- Al pulsar una cita vinculada, se abre el paciente con los permisos actuales del usuario. No concede acceso clínico a recepción.
- Reprogramación de citas agendadas, validación de solapamientos y versión del registro. Cancelaciones y reprogramaciones exigen motivo; la bitácora conserva horarios anteriores, autor y fecha del servidor. Los reintentos de la misma operación no duplican cambios.
- Nombre visible propio por clínica, editable desde Agenda. Se usa en asignaciones, pendientes, mensajes, desempeño y checado; exportaciones de servicios/asistencia conservan el ID y añaden el nombre. No se reutiliza la cédula ni la firma profesional. El nombre visible es autodeclarado, no una acreditación de identidad.
- Los nombres se incluyen en el respaldo operacional. No cambia el alcance de exportación de chats privados.
- Corrección de bajas: agenda, tareas, servicios y asistencia referencian la identidad de la cuenta y clínica para conservar el historial, sin exigir una membresía activa. Cada nueva asignación/acto sigue verificando una membresía activa. La ficha médica consentida se conserva bajo sus controles de acceso; su conservación y eventual eliminación se deben definir antes de operación real.

Ampliación de captura protegida:
- Nuevo paciente, eventos clínicos, editor de plantillas, membrete/logo, editor de documentos y formularios de ingreso/indicaciones de hospitalización avisan antes de salir con cambios pendientes.
- Bloquean retroceder mientras guardan; el éxito permite cerrar y el fallo conserva la captura.
- No guardan borradores clínicos sin cifrar en el dispositivo. El cierre de proceso o pestaña aún puede perder cambios no guardados. Los editores que no usan estos componentes y la recuperación cifrada de borradores siguen pendientes.

### Instalación final

Después de las adaptaciones existentes M2–M14 y `existing_team_management.sql`, aplicar una vez, en este orden:
1. `supabase/adaptations/existing_appointments_extension.sql`: añade nombres visibles y búsqueda; actualiza agenda, vistas y exportación, preservando la envoltura de permisos de planes.
2. `supabase/adaptations/existing_membership_history.sql`: ajusta relaciones históricas y mantiene la comprobación de membresía en nuevas capturas.

Antes de aplicarlas en producción, respaldar y revisar cualquier `patient_id` previo que no corresponda a la clínica: la nueva clave foránea rechazará ese dato. No reescribe ni elimina registros para forzar la instalación. Estas adaptaciones se probaron en PostgreSQL aislado; no se ejecutaron sobre la base remota.

### Verificación

145 pruebas Flutter aprobadas; 15 comprobaciones enfocadas adicionales pasaron tras mejorar las exportaciones. Análisis sin incidencias y compilación web de producción completada. SQL local de agenda, historial, planes, IA y soporte aprobado: paciente de otra clínica rechazado, identidad tomada del expediente, solapamiento y versión comprobados, motivos obligatorios, reprogramación idempotente y baja que conserva servicios/asistencia/ficha consentida. Pruebas de pantalla comprueban selección, descarte de búsquedas tardías, cambios sin guardar y bloqueo durante envío.

Pendientes de código que siguen abiertos: paginación general, nombres en otras áreas clínicas, restauración y cifrado de respaldos/borradores, adaptadores offline por módulo, incidencias de frascos cerrados, devoluciones parciales y anticipos/pagos divididos, ciclo completo de suscripciones, limpieza de adjuntos y navegación web. Los bloques 1–3 no equivalen a completar toda esta lista.

## Bloque 4: cifrado y revisión de respaldos

Implementado: exportación cifrada con contraseña por defecto, apertura de archivos protegidos, comprobaciones de integridad más estrictas y resumen para revisar una recuperación. La contraseña no se guarda ni se envía al servidor. Se conservan los bytes originales del archivo y las cantidades textuales del snapshot. CSV y la opción explícita JSON siguen sin cifrar.

La revisión exige la clínica correcta y rechaza archivos alterados, rutas de fotos fuera de alcance y registros mezclados. Muestra cantidades de registros y permite exportar un informe; no ejecuta una restauración. El archivo operacional no incluye todo lo necesario para reconstruir el servidor.

Verificación: 148 pruebas generales aprobadas, más el caso criptográfico completo ejecutado por separado y una comprobación nueva de pantalla/permisos; 150 casos distintos aprobados en total. Tras los ajustes de pantalla pasaron las cuatro pruebas enfocadas de respaldo sin repetir el caso criptográfico. Análisis sin incidencias. Compilación web de producción completada.

[Detalle, uso, límites y restauración pendiente](respaldo-protegido-recuperacion.md). No se crearon tablas ni se modificó el proyecto remoto. Drive, recuperación completa del servidor, exportación por lotes y cifrado de borradores/caché clínica continúan pendientes.

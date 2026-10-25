# Aislamiento y desinfección hospitalaria — candidato 14D

Estado: código y SQL locales; pendiente de la integración final. No se aplica al
servidor, no abre admisiones beta y no cambia clasificaciones clínicas.

## Recorrido

- Con permiso explícito y habilitación profesional vigente, **Indicar aislamiento**
  registra la decisión, su motivo y el protocolo revisado por la clínica: documento,
  versión/ubicación y de 1 a 30 pasos del checklist. No hay enfermedades, productos,
  diluciones, tiempos ni precauciones clínicas precargadas.
- La tarjeta del paciente hospitalizado señala **AISLAMIENTO**, jaula actual,
  motivo, referencia, persona y hora. La bandera pertenece a esta estancia; no es
  un diagnóstico permanente del expediente. También funciona sin jaula asignada.
- **Registrar acceso a aislamiento** requiere otro permiso explícito y confirma
  únicamente el acceso de quien está autenticado, su motivo y lectura del protocolo.
  No registra cuidados, medicación ni aplicaciones.
- Al cambiar de jaula, cada área expuesta queda pendiente de desinfección; si sigue
  activo el aislamiento, la nueva área se incorpora. Cambios de escritura como
  mayúsculas o espacios no representan otra jaula física.
- Retirar la bandera requiere decisión profesional y motivo. No borra las áreas
  expuestas ni las marca como limpias. La referencia y el checklist originales de
  la estancia se conservan: no pueden sobrescribirse mientras haya evidencia ligada.
- El alta conserva su contrato: revisión de indicaciones, cancelación de pendientes
  sin registrar aplicaciones ni modificar saldos. Avisa que quedan limpiezas; al
  liberar la ubicación aparecen en una cola que sigue visible después del alta.
- Para confirmar desinfección, quien tiene permiso marca cada paso que realizó y
  una confirmación final, sin casillas preseleccionadas. Se guardan su identidad,
  hora del servidor, checklist, referencia y notas opcionales.
- La jaula liberada no admite otro paciente hasta completar **todas** sus limpiezas
  pendientes. La validación del servidor contempla mayúsculas y espacios y se aplica
  tanto al ingreso como al cambio de jaula. Una ubicación sin nombre conserva una
  tarea identificada por área/estancia y no bloquea otras admisiones sin jaula.
- **Bitácora de aislamiento** consulta cambios, accesos y limpiezas, incluso después
  de completarlas y del alta. Los identificadores de personas se conservan para
  auditoría; no se inventan nombres si el directorio no los proporciona.

## Permisos y compatibilidad

`hospital.read` permite ver las alertas y la bitácora de la misma clínica.
`hospital.isolation.manage` requiere profesional verificado y habilita indicar o
retirar la bandera. `hospital.isolation.handle` habilita el registro propio de
accesos y la confirmación de limpieza. Ninguno se concede automáticamente por rol.
Los eventos nuevos también exigen `hospital.read` al consultarse por la tabla general de auditoría; la política histórica de auditoría administrativa se conserva para los demás eventos.
Las nuevas acciones no tienen alternativa por roles antiguos. Perder un contrato
ya conocido limpia la hoja y bloquea las acciones hasta actualizar.

El control implementado autoriza y audita estas acciones dentro de la app. No es
un control físico de puertas ni certifica que alguien haya entrado o limpiado.
Los permisos independientes de consulta, prescripción y administración mantienen
su contrato: un registro de acceso no los concede ni los sustituye.

SQL: `14D_hospital_isolation.sql` requiere 13G y sus dependencias (y el resto del
corte coordinado según la guía de integración). Mantiene las tablas nuevas privadas
sin acceso directo, RPC con `search_path` vacío, verificación actual de permisos,
versiones de estancia, bloqueo por clínica y recibos de operación para reintentos.
Los disparadores protegen la jaula y generan la limpieza en la misma transacción
que el cambio/alta, sin duplicar el flujo de alta. No publicar aisladamente.

La UI ofrece el bloque cuando el servidor anuncia `isolation_version = 1`; rechaza
versiones desconocidas y conserva el comportamiento previo de servidores anteriores.
El cambio intencional respecto al contrato previo es la **restricción de reutilizar
una jaula liberada con desinfección pendiente**; el alta del paciente sigue permitida.

## Validación y pendientes

`bash supabase/tests/run_hospital_isolation.sh` ejecuta PostgreSQL 17 aislado con
fixtures sintéticas, la cadena real de dependencias, regresión del alta y concurrencia.
Cubre permisos sin promoción automática, identidad, clínica ajena, anon/ACL, protocolo
vacío/duplicado, versiones, idempotencia, cambio de ubicación, jaula sin asignar,
retirada de bandera, alta, checklist incompleto, bloqueo/reutilización y revocación.
Incluye sesiones concurrentes de limpieza/asignación y revocación/acción en espera.

Flutter cubre la frontera RPC, contrato/permisos, casillas obligatorias y presentación
a 320 dp, junto con regresiones de hospitalización y peso diario.

Pendiente: aplicación remota en pruebas, cuentas Auth de dos clínicas, protocolo real
revisado por la clínica y recorrido en APK/teléfono. No sustituye la revisión de
fuentes oficiales que sigue en otros trabajos. No se agregan alarmas remotas ni un
protocolo clínico universal con este bloque.

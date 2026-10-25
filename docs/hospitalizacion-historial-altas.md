# Hospitalización: consulta de altas

## Uso

En **Hospitalización → Consultar hospitalizaciones dadas de alta**:

- Buscar por nombre de paciente dentro de la clínica activa. La búsqueda es
  literal, sin distinguir mayúsculas; `%` no se interpreta como comodín.
- Recorrer altas de más reciente a más antigua, 25 por página.
- Abrir una estancia cerrada: ingreso, alta, motivo, última jaula y autores.
- Consultar los eventos de ingreso/cambio de jaula ya conservados en auditoría.
- Recorrer sus indicaciones y resoluciones, 50 tareas por página: horario
  original, realización/cancelación registrada, autor, motivo y referencia de
  aplicación estructurada cuando exista. No se deduce una aplicación de un
  registro antiguo incompleto.

Las horas se muestran en la zona local del dispositivo. Los nombres del
personal, cuando existen, son los nombres visibles actuales autodeclarados;
los identificadores se conservan para autoría. Los eventos de jaula muestran
el identificador del autor. Un dato ausente se indica como no registrado.

La vista es de consulta: no reabre ingresos, programa avisos, confirma cuidados,
modifica aplicaciones ni mueve inventario. Los resultados detallados de cuidados,
las fotos y los documentos siguen en sus pantallas actuales. No es una exportación
integral del expediente.

## Permisos, sesiones y páginas

Requiere membresía vigente y permiso explícito `hospital.read`. Ser administrador
por sí solo no habilita esta consulta. Cada petición comprueba de nuevo ese
permiso y su vigencia. Los endpoints rechazan estancias activas, ajenas o
inexistentes con el mismo error de estancia cerrada no encontrada.

- Paginación por fecha e identificador para conservar filas con fechas iguales.
- Al cambiar la búsqueda o estancia se descartan respuestas anteriores.
- Una lectura fallida, incluida la página siguiente, retira los datos previos
  de la vista y pide actualizar permisos/conexión.
- El cambio de sesión/clínica limpia la vista y la búsqueda. Se comprueba el
  contexto antes y después de cada lectura. En la app integrada, los cambios
  de Auth invalidan la pantalla inmediatamente.
- Se vuelve a consultar cada 30 segundos mientras la pantalla está abierta;
  la actualización vuelve a la primera página. Una revocación remota se
  descubre al siguiente intento de consulta; no se promete retirar datos de
  un dispositivo desconectado de forma instantánea.
- Datos solo en memoria; no se añaden a preferencias ni a la cola offline.

Los cambios de jaula y su registro ya existían en 13D. Este bloque añade el
acceso a los ingresos cerrados y presenta esa historia junto a sus resoluciones;
conserva los controles anteriores de ingreso, alta, aislamiento y aplicaciones.

## Instalación y verificación

Candidato local: `supabase/proposed/14I_hospital_history.sql`, tras las dependencias
de 14H/14G/13G, incluido `staff_display_names`. Añade dos RPCs de lectura e índices;
no cambia las políticas de permisos ni activa el programador o el reparto de
avisos. Revisar colisiones de numeración con propuestas de otras ramas.

```bash
flutter test --no-pub test/hospital_history_test.dart
HOSPITAL_TEST_DUTY=1 HOSPITAL_TEST_HISTORY=1 bash supabase/tests/run_hospital_automation.sh
```

Pruebas con identidades/datos sintéticos: separación de clínicas, permiso
explícito y revocado, páginas con fechas iguales sin pérdidas/duplicados,
búsqueda literal, falta de sesión, contratos de respuesta, respuestas tardías,
limpieza de datos y pantalla a 320 dp con texto ampliado. El runner usa PostgreSQL
17 aislado y ejecuta las regresiones hospitalarias y de horarios previas.

14I se instaló en Supabase **Pruebas** el 24 de octubre. Se comprobó que solo
`authenticated` tiene `EXECUTE` y que una llamada sin permisos se rechaza.
Pruebas con dos cuentas reales, APK y revisión integrada de las altas siguen
pendientes. Teléfono/WhatsApp,
proveedores y activación del reparto por turno conservan sus pendientes.

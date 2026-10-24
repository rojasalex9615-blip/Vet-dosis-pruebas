# Hospitalización: alimentación y cuidados de dispositivos

Candidato en la rama de esta tarea. La conexión, el despliegue y la prueba con
cuentas reales quedan para la integración final acordada con Ale. No modifica los
lotes clínicos en revisión por otros equipos.

## Recorrido

Hospitalización → ficha del paciente → **Alimentación y catéter**:

- **Alimentación:** alimento, porción por horario, unidad (g, ml o porción) e
  indicaciones expresas del profesional.
- **Revisión de catéter:** dispositivo/sitio e indicaciones.
- **Cambio de equipo:** dispositivo/sitio e indicaciones.

Se elige un tipo de procedimiento activo de la clínica, sin seleccionarlo por el
nombre de la opción. No se crean tipos ni se infiere que una persona puede
realizarlos por su puesto. La programación y confirmación conservan el contrato
conservador profesional de 13E: `hospital.read` / `hospital.schedule`, habilitación
vigente y, para realizar, `procedure.perform` del tipo exacto. Esta entrega no
amplía las facultades del auxiliar. Documentación base:
[revisiones por procedimiento](permisos-etapa2b5.md).

## Hoja diaria y horarios

El profesional elige fechas inicial/final y horas de cada día. El cliente expande
ese periodo en horarios explícitos UTC y envía **una** llamada al RPC existente
`hospital_review_schedule`. Las tareas aparecen en las fichas y tabla diaria
paciente × hora existentes, con indicación, porción/dispositivo, estado y quién
confirmó la realización. No se marca realizado al programar ni al emitir un aviso.

El mismo horario se repite en todos los días elegidos. La fecha final es inclusiva;
no hay renovación indefinida ni un proceso de servidor que genere futuras órdenes.
La app ya puede mostrar cada fecha sin volver a crear la orden. La cancelación
por alta y la auditoría usan las rutas de hospitalización existentes.

Límites técnicos: hasta 31 fechas y 200 tareas por orden (límite del RPC). Todas las
horas deben estar en el futuro y no repetirse. No se omiten silenciosamente horas
pasadas del primer día: se pide corregir las fechas/horas. Para un primer día con
horarios diferentes, programarlo por separado. Se preserva el minuto exacto.

Las horas corresponden a la zona del dispositivo, como el contrato previo. Se
convierten una vez a UTC y se muestran para revisión. Se rechazan horas inexistentes
por cambio de horario estacional. En una hora local repetida por cambio estacional,
DateTime elige una de sus ocurrencias; no hay selector entre ambas. Si se requiere
esa distinción o una zona de clínica distinta de la del dispositivo, debe usarse
una programación explícita revisada para ese caso antes de operación real.

## Datos y guardado

No hay alimentos, porciones, intervalos, cuidados clínicos ni valores de alarma
precargados. El aviso de retraso se captura expresamente; solo controla el aviso,
no altera el tratamiento. La IA no participa.

Los datos del cuidado quedan como texto legible en `label` / `instructions` de
cada tarea de revisión. No se agregan columnas ni una tabla de órdenes paralela.
No constituyen medicación ni se envían a registro de aplicaciones, receta, frascos
o inventario. No se calcula volumen ni nutrición desde la porción.

Los borradores viven en memoria y tienen aviso al salir sin guardar. El recibo
idempotente usa la misma operación para reintentar contenido idéntico; al cambiar
contenido se genera otra. Una respuesta perdida requiere actualizar la hoja para
comprobar si se guardó; no se asume fracaso ni se reintenta automáticamente.
El servidor conserva su responsabilidad de revalidar permisos, vigencia de la
estancia y tipo activo. Fallos de lectura y permisos revocados bloquean el guardado
desde el ViewModel, incluso si el formulario estaba abierto.

## Integración final

No exige SQL nuevo; requiere el contrato de hospitalización con revisiones tipadas
13E y las dependencias del corte coordinado del proyecto. No aplicar 13E de forma
aislada: conserva las restricciones de sus documentos. El menú nuevo aparece solo
con capacidad de revisiones tipadas, tipos activos, permiso de programación y un
repositorio compatible; no se ofrece en el contrato legado por el puesto admin.

Pruebas reproducibles:

```sh
flutter analyze --no-pub
TZ=America/New_York flutter test --no-pub test/hospital_care_test.dart
flutter test --no-pub test/hospital_test.dart test/hospital_flexible_test.dart test/hospital_review_permissions_test.dart test/hospital_resolution_test.dart
```

Los tests usan identidades y cantidades ficticias; la frontera del repositorio se
comprueba con HTTP simulado sin conectarse a Supabase. Incluyen expansión de fechas,
precisión de porciones, cambio estacional, validación, ausencia de valores
predeterminados, permisos, estancia ausente, fallo de lectura, contrato RPC,
reintentos y presentación de las tareas en la hoja.

## Pendientes de hospitalización

Esta entrega cubre programación finita de alimentación y recordatorios de catéter /
equipo. Quedan el registro de consumo real y resultados/hallazgos estructurados de
cada cuidado; órdenes recurrentes con vigencia/versionado propio y generación por
servidor; pruebas rápidas;
escalación a otro integrante con confirmación y auditoría. No se certifican con este
cambio las alarmas con app cerrada o después de reiniciar.

Los avisos nuevos reutilizan el planificador local existente y su presupuesto
máximo de 60 avisos; un lote mayor no equivale a 200 alarmas nativas garantizadas.
La cancelación remota se reconcilia al volver a consultar, según los límites
existentes de [M5](m5-hospitalizacion.md). Validar ese comportamiento en teléfono y
con el servidor integrado antes de depender de los avisos en operación real.

Peso diario y selección para cálculo tienen su [bloque candidato](hospitalizacion-peso-diario.md); falta validarlo con el servidor integrado.

Aislamiento/desinfección tienen su [bloque candidato 14D](hospitalizacion-aislamiento.md), pendiente de integración remota.

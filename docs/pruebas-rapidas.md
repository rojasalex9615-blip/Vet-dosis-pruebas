# Pruebas rápidas — candidato local 14E

## Recorrido

Pacientes → abrir expediente / caso clínico → **Pruebas rápidas del caso**.
También está disponible al abrir los casos desde Formatos. La entrada siempre
pertenece a un caso y, mediante ese caso, a su paciente y clínica.

La persona captura explícitamente:

- Prueba o kit y muestra/identificación opcional.
- Fecha y hora reales de lectura, seleccionadas en hora local y enviadas en UTC.
- Banda C y banda T: visible, no visible, no puedo determinarlo o no aplica.
  Ninguna opción está preseleccionada. Las pruebas con más bandas pueden
  describirse en el resultado; aún no hay un formulario de panel multianalito.
- Resultado leído/descrito y, opcionalmente, interpretación profesional y notas
  o referencia del instructivo. Interpretación vacía se muestra **pendiente**.
- Foto PNG/JPEG opcional, hasta 8 000 000 bytes, desde cámara o galería.
  Si se cancela el selector no se crea un registro.

No hay catálogo de interpretaciones, diagnóstico por bandas/foto, rangos,
tratamientos ni tiempos de lectura inferidos. La referencia del instructivo se
captura manualmente; no acredita por sí sola una fuente verificada.

## Permisos y autoría

El nuevo contrato `clinical_rapid_tests_workspace` versión 1 exige lectura
clínica y de paciente; devuelve clínica, caso, paciente, usuario y acciones
explícitas. Un contrato ausente, desconocido o de otro contexto limpia la
pantalla y no habilita acciones por rol visual.

Registrar/interpretar requiere el procedimiento **evaluacion** configurado para
ese caso: permiso `procedure.perform` vigente, autorización del caso y
habilitación profesional vigente, tanto al observar como al guardar. Reutiliza
el contrato de 13C; no concede permisos automáticamente a administradores,
auxiliares ni al MVZ responsable. El caso debe tener configurado ese alcance
mediante su flujo actual de autorización.

El servidor fija `recorded_by` y `created_at`; no admite seleccionar otro autor.
La fecha observada no puede ser futura ni anterior a la fecha clínica. Una
corrección requiere además al responsable del caso con `clinical.authorize`;
añade una entrada con motivo y vínculo al original. La segunda corrección de
una misma versión se rechaza: se corrige la versión vigente. Se conserva todo
el historial, incluido el resultado y foto anteriores. No se reescriben ni
eliminan registros. Los reintentos idénticos conservan la clave de operación;
cambiar el contenido genera otra clave en el formulario.

## Fotografías

El bucket privado `rapid-test-photos` es independiente de
`clinical-attachments`: este último permite actualización/eliminación por su
contrato previo y no sirve como evidencia inmutable para este flujo.

- Subir requiere además `clinical.attach` y autorización de evaluación vigente.
- Ruta: `clínica/caso/operación-hashCliente.extensión`. El hash identifica los
  bytes seleccionados para reintentos; no es una certificación del contenido
  clínico ni un hash calculado por el servidor.
- La app comprueba tamaño y firma básica JPEG/PNG. Storage limita tamaño y MIME;
  el RPC comprueba existencia, propietario, ruta/caso, operación y metadatos.
- No hay políticas de actualización/eliminación para clientes. La foto ligada
  se lee solo con acceso al caso; el autor autorizado puede leer su carga aún
  no ligada. La lectura usa descarga autenticada; no se publica una URL abierta.
- Si la subida termina pero el registro falla, puede quedar una carga sin ligar.
  El reintento conserva la misma ruta. La limpieza de huérfanos requiere una
  tarea del servidor con retención acordada: no hay borrado desde esta pantalla.
- Una corrección admite otra foto opcional; la anterior permanece en el original.

Los resultados y fotos solo se mantienen en memoria de este flujo. No hay cola
offline, exportación PDF ni generación automática de órdenes.

## Integración y verificación

`supabase/proposed/14E_clinical_rapid_tests.sql` es una migración candidata,
posterior a 13C y al esquema Storage. En la integración ordinaria se aplica tras
13X/14D. Requiere beta cerrada/permisos aún sin corte global; no abre admisiones
ni activa políticas generales. Las instalaciones ya abiertas necesitan un plan
de migración revisado antes de desplegarla.

Pruebas seleccionadas:

```bash
flutter analyze --no-pub
flutter test --no-pub test/rapid_tests_test.dart --reporter expanded
bash supabase/tests/run_rapid_tests.sh
flutter test --no-pub --reporter expanded
```

El runner PostgreSQL 17 reutiliza la cadena base y los tests de permisos
clínicos y Storage, y verifica autoría, reintentos, correcciones inmutables,
permisos por procedimiento, límites de datos, fotos inexistentes/ajenas,
revocación y aislamiento. El fixture local modela `owner_id`; no ejecuta el
servicio HTTP de Supabase Storage ni valida binarios reales.

Pendiente de integración final: aplicar remotamente, probar con dos sesiones
Auth/clínicas, subida/descarga real y sus límites, cámara/galería en APK firmado
y la recuperación tras pérdida de conexión. No se ha conectado ni desplegado
esta entrega en el proyecto remoto.

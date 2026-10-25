# Peso diario de hospitalización — candidato, 24 octubre 2026

## Recorrido

1. Hospitalización → paciente → **Peso diario**. Consulta los pesos observados
   durante esta estancia en los casos clínicos a los que tienes acceso.
2. La pantalla indica si hay una medición de hoy; el día usa la zona local del
   dispositivo. Actualiza al cambiar de día o para comprobar cambios de acceso.
   El aviso se limita a las mediciones accesibles: no certifica que nadie más haya
   pesado al paciente en un caso que no puedes consultar.
3. Selecciona explícitamente un caso clínico existente. **Registrar peso** exige
   permiso vigente para observaciones en ese caso; no crea casos ni asigna permisos.
4. Captura kg, fecha/hora observada y notas opcionales. Confirma paciente, valor y
   hora de una medición que tú realizaste. No hay un peso ni una hora precargados.
5. Queda como observación clínica con autor, registrador y fecha del servidor.
   La vista muestra esos identificadores, el caso y la medición para auditoría.
   Las correcciones siguen el flujo del responsable en el caso clínico; aquí se
   excluyen las mediciones reemplazadas, sin borrar originales.
6. MVZ/admin con acceso a Cálculo rápido puede elegir **Revisar peso para cálculo**.
   Allí revisa paciente, fecha y autor y pulsa **Usar peso registrado**. El campo
   de peso conserva el decimal capturado y no permite editarlo en ese cálculo;
   para corregirlo debe volver al caso clínico.
7. Se comprueban estancia activa, contexto de cuenta/clínica, acceso clínico y
   vigencia de la misma medición al abrir, usar, calcular y confirmar. Un fallo
   impide continuar y borra peso/resultado del cálculo. No se elige automáticamente
   el peso más reciente ni se establece una antigüedad clínicamente aceptable.

## Contratos conservados

- Escribe únicamente mediante `clinical_observation_add`, con `performed_by`
  fijado al usuario actual y el identificador de operación del formulario para
  reintentos. La RPC ya genera el evento del expediente; no hay una segunda escritura.
- Usa `clinical_workspace`, casos y snapshots existentes; requiere contrato
  explícito antes de leer filas. La cuenta visual de admin no sustituye permisos.
- Solo acepta kg positivos exactos, dentro de la estancia y no futuros. La RPC
  conserva sus validaciones de fecha del caso, autoría y permisos en hora observada.
- Los snapshots PostgreSQL devuelven decimales como texto y horas con zona;
  se conservan precisión y equivalencia UTC. El formulario envía UTC estricto.
- Se consulta por lotes de hasta cuatro casos en paralelo, sin recortar el historial
  a una cantidad arbitraria. Si falla un caso, se limpia la lista completa.
- Motor, fuentes, validaciones y doble confirmación de dosis se mantienen. Elegir
  peso no verifica un catálogo ni produce una receta o administración. El cálculo
  rápido genérico conserva la captura manual de peso.

## Validación e integración pendiente

Pruebas locales con datos aritméticos ficticios: kg exactos, fechas con zona,
identidad y alcance de clínica/paciente/caso, correcciones, permiso ausente o
revocado, alta, fallo de guardado/reintento, respuestas tardías, pantalla de 320 dp,
selección explícita y revocación de la fuente durante la confirmación del cálculo.

La conexión remota queda para el final por instrucción del usuario. No se aplican
migraciones, no se publican fuentes clínicas ni se compila un APK con este bloque.
Falta ejecutar el recorrido con cuentas y casos reales del entorno de pruebas y
verificar zona horaria/configuración del teléfono. Las comprobaciones previas de
estancia son lecturas; esta entrega no agrega una transacción SQL que una el estado
de hospitalización al guardado de una observación ni una suscripción en tiempo real.
Las órdenes y recetas vigentes no se recalculan automáticamente.

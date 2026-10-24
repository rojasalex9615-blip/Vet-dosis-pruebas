# Hospitalización: resultados de cuidados (candidato 14F)

Implementado en la rama de la tarea; instalación remota, cuentas reales y APK
pendientes de la integración final. No se han conectado ni modificado servidores.

## Recorrido y alcance

Hospitalización → tarea de revisión → **Resultado del cuidado**. También existe
**Historial de resultados de cuidados**, que permite consultar antecedentes de
estancias ya dadas de alta. El servidor debe anunciar `care_results_version: 1`;
la interfaz no ofrece estas acciones en versiones anteriores.

La persona selecciona expresamente alimentación, revisión de catéter, cambio de
equipo u otro cuidado. No se deduce el tipo a partir del nombre de la tarea.
Captura fecha/hora real y hallazgos, e indica que realizó personalmente el cuidado.
No se precargan hallazgos normales, instrucciones ni valores clínicos.

En alimentación se requieren cantidad realmente ofrecida, cantidad consumida y
una unidad común (g, ml o porción). Se permiten cero consumido y hasta nueve
cifras decimales; se rechazan cantidades negativas, ofrecido cero o consumo mayor
que lo ofrecido. No calcula nutrición ni decide una porción. La confirmación de
una tarea no significa que el paciente consumió toda la porción.

Guardar un resultado de una revisión pendiente confirma la tarea y agrega el
resultado en una sola transacción. Si el resultado es inválido, tampoco queda
confirmada la tarea. La confirmación genérica existente sigue disponible; su
realizador puede anexar posteriormente su resultado sin confirmarla otra vez.
Los resultados no se aplican a tareas de medicación, recetas, frascos o inventario.

## Autoría, permisos y correcciones

Conserva el contrato de 13E: lectura `hospital.read`, profesional habilitado y
`procedure.perform` vigente para el tipo exacto. No concede permisos por nombre,
rol admin ni texto de la indicación. La observación requiere autoridad también en
su fecha; no puede preceder al ingreso, horario o posposición, ser futura ni ser
posterior a la confirmación ya registrada.

El servidor asigna persona y fecha de registro, guarda el permiso utilizado y
escribe auditoría. Solo quien realizó la tarea puede anexar/corregir su resultado.
Las correcciones requieren motivo, conservan originales y solo pueden sustituir
el último registro de su cadena. El alta mantiene la consulta histórica y permite
corregir resultados propios con autoridad vigente; no permite realizar tareas
canceladas. El historial general es de consulta.

La operación conserva versión, contenido y clave durante un reintento idéntico
tras pérdida de respuesta. Cambiar el contenido genera otra clave. Cada llamada
vuelve a comprobar permisos antes de devolver un recibo; una revocación impide
utilizar el reintento para eludirla. No hay reintentos automáticos ni guardado
clínico offline. Los borradores permanecen en memoria con aviso al salir.

## Integración y pruebas

`supabase/proposed/14F_hospital_care_results.sql` es un candidato local. Requiere
la cadena de permisos/revisiones/resolución hasta 13G y el snapshot 14D, con sus
adaptaciones y prerrequisitos; no depende de las tablas de pruebas rápidas 14E.
No aplicar por numeración sin revisar el esquema integrado: las propuestas de
otras ramas pueden usar números coincidentes. La migración exige beta cerrada y
permisos globales todavía inactivos; no abre la beta ni activa el corte.

```sh
flutter analyze --no-pub
flutter test --no-pub test/hospital_care_results_test.dart
bash supabase/tests/run_hospital_care_results.sh
```

Pruebas sintéticas Flutter: cantidades exactas, ausencia de valores implícitos,
contratos/alcance, correcciones, revocación visual, capacidad perdida, formulario
a 320 dp, respuesta tardía y reintento con versión/clave estables. PostgreSQL 17:
confirmación/resultado atómicos, reversión de datos inválidos, permisos/autoría,
historial inmutable, alta, reintentos y concurrencia con revocación; incluye las
regresiones previas de resolución e aislamiento. No son pruebas con usuarios
reales ni certificación de alarmas o funcionamiento del teléfono.

Pendientes: despliegue revisado, dos sesiones/clínicas reales, operación en APK,
hoja automática/recurrencia en servidor y escalación al MVZ. Estas últimas no se
consideran completadas por registrar resultados.

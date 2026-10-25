# Integración de hospitalización en Supabase Pruebas

El 24 de octubre de 2026 se aplicaron, en el proyecto **Pruebas**
(`wtrelwtztkddfktrfdpb`), los bloques 14I, 14D, 14E, 14F, 14G y 14H del
repositorio. El orden de ejecución de 14I fue seguro para este esquema porque
ya existían `hospital_stays`, `hospital_tasks`, `staff_display_names`,
`hospital_cage_history` y el permiso explícito `hospital.read`. Los demás
bloques se aplicaron en el orden 14D–14H.

Verificación posterior:

- Las funciones de aislamiento, pruebas rápidas, resultados de cuidados,
  órdenes, horarios y consulta de altas existen. Su ejecución se concede a
  `authenticated`, no a `anon`.
- Las tablas privadas nuevas tienen RLS y no conceden SELECT directo a
  `authenticated`.
- `rapid-test-photos` es un bucket privado.
- `hospital_automation_runtime.enabled = false` y
  `duty_routing_enabled = false`. No había órdenes ni avisos al comprobarlo.
- `pg_cron` no está instalado; no se programó trabajo alguno.
- Las funciones de consulta de altas rechazaron una llamada sin sesión con
  `explicit_permission_required`.
- La suite SQL local de PostgreSQL 17 y el workflow Flutter/SQL del PR #23
  habían aprobado antes de la instalación.

Esto **no certifica** el recorrido con dos cuentas reales y dos clínicas, la
lectura de fotos en APK, la entrega de avisos con la app cerrada ni el
programador. No se activaron teléfono o WhatsApp. Esos pasos deben verificarse
antes de habilitar órdenes automáticas y reparto por turno.

Los asesores de seguridad de Supabase muestran avisos informativos por tablas
`private` con RLS sin políticas, coherentes con el acceso exclusivo por RPC, y
avisos generales por funciones `SECURITY DEFINER` ejecutables por usuarios
autenticados. Cada RPC nuevo contiene comprobaciones de membresía y permiso;
seguir auditando esas rutas con cuentas reales antes de abrir la beta.

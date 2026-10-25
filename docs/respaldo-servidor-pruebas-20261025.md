# Respaldo del servidor de pruebas — 25 de octubre de 2026

La base PostgreSQL de Supabase Pruebas se exportó y cifró en la ejecución
[40178192626](https://github.com/rojasalex9615-blip/Vet-dosis-pruebas/actions/runs/40178192626).
El archivo se descifró y restauró en una base aislada sin red en la ejecución
[40178339771](https://github.com/rojasalex9615-blip/Vet-dosis-pruebas/actions/runs/40178339771).
La verificación de tablas y conteos pasó. No se modificó la base activa.

El flujo `backup-test-database.yml` crea una copia cifrada diariamente a las
08:17 UTC y conserva el artefacto siete días en GitHub Actions. Depende de que
Actions, los secretos del repositorio y Supabase estén disponibles. El ensayo
de migraciones sobre una copia ya actualizada es opcional y separado de la
verificación de restauración.

El flujo `backup-test-storage.yml` creó una copia cifrada de **1 objeto de
38 832 bytes** en la ejecución
[40179599273](https://github.com/rojasalex9615-blip/Vet-dosis-pruebas/actions/runs/40179599273).
La [recuperación aislada del artefacto](https://github.com/rojasalex9615-blip/Vet-dosis-pruebas/actions/runs/40179755486)
comprobó el hash cifrado, manifiesto y SHA-256 del binario, sin conectarse al
proyecto activo. Quedó programada diariamente a las 08:37 UTC, también con
retención de siete días. Usa una clave de servicio obtenida solo durante la
ejecución con el token administrativo; no la publica ni la guarda como archivo.

**Alcance:** la copia de PostgreSQL contiene base y metadatos de Storage; la
segunda contiene los binarios. Son dos capturas separadas, sin snapshot atómico
común. Aún faltan un ensayo de recuperación conjunta, secretos/configuración
de plataforma e identidades globales de roles, una copia fuera de GitHub y una
política de retención más larga. No se afirma recuperación completa del servicio.

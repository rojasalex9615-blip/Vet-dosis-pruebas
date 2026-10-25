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

**Alcance:** este respaldo contiene la base y metadatos de Storage. Todavía no
incluye los binarios de Storage, secretos de plataforma ni identidades globales
de roles. Tampoco equivale a una restauración completa del servicio. Pendiente:
copiar/cifrar binarios con manifiesto de hashes, conservarlos fuera del runner,
ensayar su recuperación junto con la base y definir retención más larga.

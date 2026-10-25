# Modo revisión: primera entrada del catálogo comercial

El rol `revisor` puede iniciar sesión y abrir **Modo revisión**. La navegación
oculta los módulos clínicos a ese rol. Cada lectura de datos continúa sujeta a
la comprobación de membresía en el servidor; el filtro de pantalla no sustituye
esa autorización.

La vista muestra un aviso permanente: **SIN VERIFICAR — solo revisión, no usar
con pacientes**. Busca y pagina productos del catálogo comercial mediante
`review_catalog_list`, muestra la fuente y permite enviar un comentario con
valor esperado y referencia de fuente. El reporte conserva la versión y el
snapshot visto, además del usuario y la hora registrados por el servidor.
Una lectura fallida retira las filas previas. No hay caché offline ni entrada
al motor de dosis, receta, aplicación o inventario.

Este bloque consume los RPC `review_catalog_list` y
`review_catalog_progress` y la tabla `catalog_review_reports`, presentes en
el proyecto Supabase **Pruebas** al corte del 24 de octubre. Su definición aún
no está versionada en este repositorio: antes de instalar en otro proyecto hay
que conciliar el esquema remoto y añadir una migración revisada. No se ha
instalado ni modificado SQL remoto en este bloque.

## Pendientes antes de abrir la revisión a Johana y profesores

- Comprobar el acceso con una cuenta `revisor` real y el catálogo en APK.
- Foto opcional del reporte: no existe un bucket específico autorizado para
  ese archivo; requiere política privada y prueba de acceso por clínica.
- Estados `en revisión`, `verificado`, `corregido` y `rechazado`: el RPC remoto
  de cambio existe, pero falta exigir y registrar una decisión con fuente y
  revisión profesional antes de exponerlo en la app. Enviar comentarios no
  cambia el estado de la fila.
- El catálogo comercial remoto tiene 687 filas (682 `sin_verificar` y 5
  `revisar_conflicto`) al corte. La cifra de 1,384 del handoff es histórica y
  no equivale al contenido de esta tabla. Las referencias fisiológicas,
  laboratorio y producción tienen rutas de publicación separadas.
- La base remota y el repo necesitan reconciliarse antes de desplegar estas
  funciones en otro entorno.

# Catálogo de servicios en la beta firmada

La pantalla **Servicios** muestra categorías y subcategorías editables por
clínica. Los nombres sugeridos no crean servicios automáticamente ni fijan
precios; el administrador elige nombre, precio y comisión al guardar. Las
cirugías conservan un nombre de procedimiento editable. Los servicios ya
existentes sin clasificación se muestran en **Otros servicios**.

La base de Supabase Pruebas ya contiene `category` y `subcategory` en
`clinic_services`. Para reproducir el esquema desde una instalación previa se
aplican, en orden, `13B1_permission_clinic_operations.sql`,
`13B2_restore_module_navigation.sql`, `13B3_service_categories.sql` y
`13B4_service_subcategories.sql`. El ensayo SQL comprueba permisos y las dos
rutas de actualización (con y sin 13B3), sin instalar nada en producción.

Este cambio no altera el cálculo ni la liquidación de comisiones. La cuenta
individual del colaborador, cobros parciales y devoluciones siguen pendientes
de integración y pruebas con usuarios reales.

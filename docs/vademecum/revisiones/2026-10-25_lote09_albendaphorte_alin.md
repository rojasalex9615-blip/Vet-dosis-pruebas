# VetDosis — Revisión documental comercial, lote 09 (2026-10-25)

**Proyecto Supabase:** `wtrelwtztkddfktrfdpb`  
**Esquema:** `vetdosis_reference_staging` (tablas privadas `commercial_product_enrichment` y `commercial_label_regimens`).  
**Resultado confirmado por lectura posterior:** 8 fichas nuevas y 27 instrucciones/pautas comerciales documentadas; no se modificaron registros clínicos ni se habilitó cálculo automático.

> Alcance: transcripción estructurada y paráfrasis de documentación de fabricantes o fichas PLM suministradas por laboratorios. **No equivale a validación clínica por MVZ ni a comprobación de etiqueta física vigente.** Los datos sin respaldo permanecen sin completar.

| Producto | Concentración/forma y especie | Pautas guardadas | Estado | Fuente |
| --- | --- | ---: | --- | --- |
| ALBENDAPHORTE 2.5% Co | Suspensión oral ovinos/caprinos: albendazol 25 mg/mL, sulfato cobalto 3.2 mg/mL; 200 mL y 1 L | 2 | PLM, posible desactualización | https://www.diccionarioveterinarioplm.com/albendaphorte_25_co-42-1617-109-73-2 |
| ALBENDAPHORTE 25% Co | Suspensión oral bovinos: albendazol 250 mg/mL, sulfato cobalto 32.5 mg/mL; 2 x 2 L | 2 | PLM, posible desactualización | https://www.diccionarioveterinarioplm.com/albendaphorte_25_co-42-14867-109-73-2 |
| ALBENDAZOL + TRICLABENDAZOL | Suspensión oral bovinos/ovinos/caprinos: 100 mg/mL de **cada** activo; 250 mL, 1 y 5 L | 4 | Fabricante comprobado | https://www.cheminovavet.mx/wp-content/uploads/2025/02/FTC-AlbendazolTriclabendazol.pdf |
| ALBENVET 10% | Suspensión oral bovinos: albendazol 100 mg/mL, sulfato cobalto 13 mg/mL; 240 mL y 1 L | 3 | **Conflicto** | https://www.diccionarioveterinarioplm.com/albenvet_10-76-5357-21-9-2 |
| ALBENVET 2.5 | Suspensión oral ovinos/caprinos: albendazol 25 mg/mL; 240 mL y 1 L | 4 (incluye excepción en tabla) | **Conflicto** | https://diccionarioveterinarioplm.com/albenvet_25-76-3226-21-9-2 |
| ALDESAN | Desinfectante de instalaciones, no medicamento: glutaraldehído 15 g/100 mL, amonio cuaternario 10 g/100 mL; bidón 20 L | 4 instrucciones ambientales, **rechazadas para uso clínico** | Fabricante comprobado | https://sanfersaludanimal.com/producto/aldesan |
| ALIN OFTÁLMICO | Solución caninos/felinos: dexametasona fosfato 0.90 mg/mL, neomicina base 3.50 mg/mL; 10 mL | 2 (gota fija por animal, frecuencias distintas) | Fabricante y PLM | https://www.chinoinveterinaria.com/sitio/alin_oftalmico_v2.html |
| ALIN VETERINARIO | Solución inyectable: dexametasona base equivalente 2 mg/mL; 50 y 100 mL | 6 (rangos fijos, una dosis fija, una instrucción IA especial) | PLM, posible desactualización | https://www.diccionarioveterinarioplm.com/alin_veterinario-76-393-10-13-2 |

## Alertas de integridad documental

1. **ALBENVET 10%:** para nematodos el texto señala 5.5 mg/kg, pero 5 mL/100 kg de una suspensión 100 mg/mL equivalen a **5 mg/kg**. No resolver automáticamente.
2. **ALBENVET 2.5:** profilaxis de Fasciola: 4.5 mg/kg textual frente a 2 mL/10 kg = **5 mg/kg**. Además, la fila curativa de **20 kg = 5 mL**, mientras el resto de la tabla sigue 3 mL/10 kg (serían 6 mL a 20 kg). Se registró excepción puntual, no banda de peso.
3. **ALBENDAZOL + TRICLABENDAZOL:** la fuente tiene **dos ingredientes a 100 mg/mL cada uno**. Los valores mg/kg de la tabla no asignan inequívocamente la cantidad a cada ingrediente; se guardó la pauta volumétrica literal sin inferir la dosis por activo. Ficha oficial Cheminova y PLM: https://www.diccionarioveterinarioplm.com/albendazol_triclabendazol-76-16304-21-12-2
4. **ALDESAN:** el índice de ingredientes PLM incluye un virus Newcastle no presente en la fórmula oficial del desinfectante. Las diluciones 1:150, 1:1000, 1:1500 y 1:3000 son instrucciones **ambientales**, no dosis para pacientes. La documentación incluye una instrucción de primeros auxilios potencialmente insegura (inducir vómito); **no** incorporarla como recomendación clínica.
5. **ALIN OFTÁLMICO:** no usar en queratitis ulcerativa; la duración se deja al criterio veterinario. La fuente PLM advierte posible desactualización.
6. **ALIN VETERINARIO:** los rangos son **mg por animal por día**, no mg/kg; la administración intraarticular describe una maniobra especial que **no** debe traducirse a un cálculo automático. Restricciones gestación, enfermedad endocrina, infecciones, retiro carne 21 días/leche 72 horas; no administrar a equinos destinados a consumo.
7. **ALBENDAPHORTE 2.5/25:** son formulaciones diferentes (25 y 250 mg/mL), ambas con advertencia de posible desactualización; en 25% se excluye uso en hembras que producen leche para consumo.
8. **Tiempos de retiro diferentes por marca y formulación:** nunca trasladarlos entre productos: ALBENDAPHORTE 27 días carne; ALBENVET 10% 2 días carne/48 h leche; ALBENVET 2.5 27 días carne/48 h leche; Cheminova 28 días carne y leche no apta; ALIN VETERINARIO 21 días carne/72 h leche.

## Clasificación de las 27 pautas

- 9 pendientes de revisión clínica.
- 9 pendientes de etiqueta vigente.
- 5 con conflicto documental.
- 4 instrucciones ambientales rechazadas como dosis clínicas.

**Lectura posterior de Supabase (2026-10-25):** `index_only=1256`, `plm_detail_checked=53`, `manufacturer_checked=48`, `conflict=27`; total 1,384, revisadas 128. Ningún registro clínico alterado.

**Nota de trazabilidad:** la columna `label_instruction_summary` guarda paráfrasis breves de fichas originales, no fotografías del empaque físico; no afirmar que se verificó la etiqueta comercial impresa. 

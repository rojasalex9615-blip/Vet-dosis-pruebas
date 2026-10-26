# VetDosis — Vademécum comercial, lote 10 (2026-10-25)

**Proyecto:** Supabase Pruebas `wtrelwtztkddfktrfdpb`. **Tablas privadas:** `vetdosis_reference_staging.commercial_product_enrichment` y `vetdosis_reference_staging.commercial_label_regimens`.

**Lectura posterior:** 8 registros de producto pasaron de `index_only` a estado documental; 13 pautas/instrucciones de etiqueta se guardaron y releyeron. No se alteraron tablas clínicas ni se habilitó cálculo/prescripción automática. 7 pautas `pending_clinical_review`, 4 `conflict_needs_resolution`, 1 `needs_current_label` y 1 `rejected` para dosificación de pacientes.

**Alcance:** paráfrasis estructurada de páginas de fabricantes, catálogo oficial de 2024 y páginas técnicas PLM. No se verificaron envases físicos ni vigencia registral ante autoridad; los valores documentados **no son recomendaciones clínicas MVZ**. Las pautas con unidades en conflicto no deben normalizarse.

| Ficha de intake | Identidad / concentración / presentación | Pautas guardadas | Estado documental |
|---|---|---:|---|
| ALKOSEL 3000 | Levadura inactivada enriquecida, Se total mínimo 3,000 mg/kg, 98% orgánico; bolsa 20 kg. Especies: bovinos, equinos, ovinos, caprinos, porcinos, aves. | 1 | PLM revisado |
| ALPHACEF | Cefixima trihidratada equivalente a 1 g o 2.5 g/frasco, reconstituir a 50 mL = 20 o 50 mg/mL. Perros y gatos. Frasco 20 g polvo + pipeta según fabricante. | 4 | Fabricante revisado |
| ALVEUM | Jarabe 100 mL. Por mL: bromhexina 0.065 mg, guaifenesina 3.5 mg, meloxicam 3 mg. Caninos/felinos. | 1 | Fabricante 2024 |
| AMIBAC | Metronidazol **500 mg/tableta en catálogo fabricante 2024**, caja 24. Perros/gatos. PLM imprime **3 mg/tableta**. | 2 | CONFLICTO |
| AMIKAVET-PE | Amikacina base 5 g/100 mL (50 mg/mL), viales 25/50/100 mL. Perros/gatos. | 2 | PLM revisado |
| AMINO-VIT | Por 500 mL: aminoácidos 2.5 g, dextrosa 25 g, B1 50 mg, B2 5 mg, B3 250 mg, B5 25 mg, B6 50 mg, NaCl 900 mg, MgCl2 500 mg, KCl 650 mg, propilparabeno 125 mg; formaldehído 2.4 mL fabricante vs 2.4 mg PLM. Frasco 500 mL. Bovinos/equinos/ovinos/caprinos/porcinos/perros/gatos. | 2 | CONFLICTO |
| AMINOFORTE F (PETMEDICA) | Solución aminoácidos/electrolitos/vitaminas/dextrosa, composición completa por 100 mL guardada en enriquecimiento. Frascos 250/500 mL, registro Q-0616-044. | 1 | PLM revisado |
| AMINOFORTE F (AGROVETMARKET) | Misma fórmula, nombre, registro y pauta que entrada PETMEDICA; PLM lista 100/250/500 mL. | 0, vinculado | PLM revisado |

## Pautas e instrucciones documentadas (resúmenes, no transcripción extensa)

1. **ALKOSEL:** mezcla en alimento, **100 g/tonelada**, máximo 0.3 mg Se/kg ración según PLM. Tipo `feed_concentration`; **excluida de dosificación clínica por paciente**. El fabricante confirma que es levadura inactivada con selenio orgánico, no medicamento.
2. **ALPHACEF 1 g / 20 mg/mL, infecciones sistémicas:** caninos/felinos 10–12.5 mg/kg = 2–2.5 mL/4 kg, cada 12 h durante 7–14 días. Tipo `label_complex` (rango proporcional).
3. **ALPHACEF 1 g, infecciones urinarias:** 5 mg/kg = 1 mL/4 kg, cada 12–24 h por 7–14 días. Tipo `proportional_weight`.
4. **ALPHACEF 2.5 g / 50 mg/mL, infecciones sistémicas:** 10–12.5 mg/kg = 2–2.5 mL/10 kg, cada 12 h por 7–14 días. Tipo `label_complex`.
5. **ALPHACEF 2.5 g, infecciones urinarias:** 5 mg/kg = 1 mL/10 kg, cada 12–24 h por 7–14 días. Tipo `proportional_weight`. Todas orales, después de reconstituir a 50 mL; fabricante: usar hasta 7 días a temperatura ambiente o 14 en refrigeración. Precauciones: alergia, anticoagulantes, insuficiencia renal.
6. **ALVEUM:** caninos/felinos 1 mL/15 kg oral cada 24 h por 7 días; posible segundo periodo de 7 días según MVZ. Tipo `proportional_weight`. Evitar gestantes, lactantes y <4 meses; precaución renal, hipovolemia, hipotensión, otros nefrotóxicos.
7. **AMIBAC caninos:** 1 tableta por banda de **20–30 kg**, oral cada 12–24 h por 5–7 días. Tipo `weight_band`. **Conflicto 500 vs 3 mg/tableta**.
8. **AMIBAC felinos:** 1/4 tableta por banda de **5–7.5 kg**, oral cada 12–24 h por 5–7 días. Tipo `weight_band`. Contraindicado en animales destinados al consumo humano, gestantes, lactantes, debilitados o con hipersensibilidad; cautela hepática.
9. **AMIKAVET-PE caninos/felinos:** 0.2 mL/kg por IM o SC; PLM indica duración 5–7 días **sin frecuencia**. Tipo `proportional_weight`. No inferir intervalo. Advertencias sobre nefrotoxicidad, ototoxicidad y bloqueo neuromuscular.
10. **AMIKAVET-PE infusión intrauterina:** dilución de 8 mL del producto en 200 mL de solución salina, vía intrauterina; especie e intervalo específicos no desglosados. Tipo `label_complex` (pauta especial de dilución).
11. **AMINO-VIT fabricante:** **2–10 mL/kg**, oral/SC/intraperitoneal/IV, 1–3 aplicaciones/día durante 1–3 días. Tipo `label_complex`, bloqueada por conflicto.
12. **AMINO-VIT PLM:** **2–10 mL/paciente** sin ajuste por kg, vías iguales; frecuencia a criterio MVZ. Tipo `fixed_range`, bloqueada por conflicto. Fabricante afirma 250 dosis mínimas de 2 mL por frasco de 500 mL, lo que no resuelve la contradicción del denominador. También difiere unidad de formaldehído (mL vs mg). Fabricante reporta retiro carne/leche 0 horas; hipersensibilidad y no mezclar.
13. **AMINOFORTE F (pauta compartida):** 1 mL/5 kg, 1–3 veces al día, IV/IM/SC/intraperitoneal; **equinos sólo IV**. Tipo `proportional_weight`. Infusión lenta, máximo 25 mL por punto SC, hipersensibilidad. PLM indica sin periodo de retiro. **No se duplicó la pauta** en la segunda ficha comercial del mismo registro.

## Alertas de calidad y actualidad

- **Crítica AMIBAC:** catálogo oficial Aranda 2024, 500 mg/tableta, frente a PLM 3 mg/tableta; las dos pautas están `conflict_needs_resolution`. No calcular con ninguna cifra hasta etiqueta actual.
- **Crítica AMINO-VIT:** fabricante y PDF oficial señalan mL/kg, PLM mL/paciente; la cifra de 250 dosis mínimas por frasco apoya un uso por paciente, pero no permite resolver la ficha. Además, formaldehído 2.4 mL fabricante frente a 2.4 mg PLM. Ambas pautas bloqueadas.
- **ALVEUM:** 3.5 mg de guaifenesina/15 kg = 0.233 mg/kg, mientras la equivalencia impresa dice 0.2 mg/kg; bromhexina 0.065/15 = 0.00433 frente a 0.004 mg/kg impreso. No se modificó el dato del fabricante. Catálogo 2024 requiere cotejo de etiqueta vigente.
- **ALPHACEF:** fabricante diferencia dosis sistémica 10–12.5 mg/kg y urinaria 5 mg/kg en caninos/felinos; PLM sólo lista 5 mg/kg en cánidos. Presentación PLM menciona 20/50 g de polvo, fabricante 20 g para las dos potencias. No confundir 20 y 50 mg/mL.
- **AMINOFORTE F:** dos entradas PLM con igual fórmula, registro Q-0616-044 y pauta; presentaciones difieren. Se mantuvieron dos fichas documentales pero sólo una pauta.
- **AMIKAVET-PE:** duración de 5–7 días no equivale a intervalo entre aplicaciones; no se inventó.
- **ALKOSEL:** pauta por tonelada de alimento, no por kg de peso vivo. Evitar exceso de selenio total.
- **Retiro no documentado** no significa retiro cero. Sólo se consignaron tiempos cuando las fuentes lo expresaron.

## Fuentes (consulta 2026-10-25)

- Lallemand fabricante: https://www.lallemandanimalnutrition.com/es/mexico/productos/alkosel-3000/
- ALKOSEL PLM: https://www.diccionarioveterinarioplm.com/alkosel_3000-102-10934-142-240-2
- ALPHACEF fabricante: https://alphachem.mx/alphacef/
- ALPHACEF PLM: https://www.diccionarioveterinarioplm.com/alphacef-76-5361-109-113-2
- Aranda fabricante, catálogo mascotas 2024, página PDF 3 (índice 2): https://aranda.vet/wp-content/uploads/2024/09/Catalogo_APETS24_Small.pdf
- ALVEUM PLM: https://www.diccionarioveterinarioplm.com/alveum-76-16438-39-351-2
- AMIBAC PLM: https://www.diccionarioveterinarioplm.com/amibac-76-16439-158-351-2
- AMIKAVET-PE PLM: https://www.diccionarioveterinarioplm.com/amikavet-pe-10-1118-10-1-2
- AMINO-VIT fabricante: https://panavet.com.mx/catalog/panavet-amino-vit.html
- AMINO-VIT PDF fabricante: https://www.panavet.com.mx/catalog/tech-profiles/panavet-amino-vit.pdf
- AMINO-VIT PLM: https://www.diccionarioveterinarioplm.com/AMINO-VIT-175-10917-148-57-2
- AMINOFORTE F PLM PETMEDICA: https://www.diccionarioveterinarioplm.com/aminoforte_f-76-16130-257-346-2
- AMINOFORTE F PLM AGROVETMARKET: https://www.diccionarioveterinarioplm.com/aminoforte_f-76-6898-148-78-2

## Lectura posterior de Supabase

Estados generales: `manufacturer_checked=50`, `plm_detail_checked=57`, `conflict=29`, `index_only=1248` (total 1,384; revisadas 136). Las 8 filas del lote se releyeron con `medical_review_state='needs_review'`; la segunda entrada AMINOFORTE F conserva cero pautas nuevas para evitar duplicidad.

**No se han creado ni alterado datos de pacientes, recetas, farmacología clínica validada ni habilitado dosificación automática.**

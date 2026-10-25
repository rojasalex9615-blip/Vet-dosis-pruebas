# Avisos hospitalarios por FCM y WhatsApp — preparación 14J

La migración `supabase/proposed/14J_hospital_external_delivery.sql` agrega
destinos consentidos por integrante, una entrega por aviso/canal y una cola
privada. Se instala después de 14G, con `external_delivery_enabled=false`.
No concede permisos ni activa envíos. La función `hospital-delivery` acepta solo
un secreto de despacho del servidor; usa el rol de servicio para reclamar lotes.
Al encender el transporte se fija la hora de activación; avisos anteriores no se
despachan retroactivamente.

Cada reclamación vuelve a comprobar la membresía, permisos hospitalarios,
designación MVZ cuando corresponde, consentimiento, tarea pendiente, estancia
activa y ausencia de respuesta. Un destino revocado no vuelve a reclamarse.
La cola conserva intentos, resultado y referencia del proveedor; reintenta con
espera progresiva hasta ocho intentos. La función nunca envía nombre del
paciente, indicación, dosis ni detalles de la tarea: FCM muestra un aviso
genérico; WhatsApp usa una plantilla `es_MX` aprobada y sin variables clínicas.
Abrir la app y responder el aviso sigue siendo distinto de realizar el cuidado.

## Configuración pendiente antes de activar

1. Crear el proyecto Firebase de la beta, registrar la app Android con su
   identificador real y configurar la recepción/token FCM en Flutter.
2. Crear la cuenta de WhatsApp Business Cloud API, número remitente y plantilla
   `hospital_alert` (o el nombre finalmente aprobado). Confirmar consentimiento
   y titularidad del número de cada integrante, y ofrecer revocación visible.
3. Guardar en secretos de Supabase Edge Functions:
   `HOSPITAL_DISPATCH_SECRET`, `HOSPITAL_FCM_PROJECT_ID`,
   `HOSPITAL_FCM_CLIENT_EMAIL`, `HOSPITAL_FCM_PRIVATE_KEY`,
   `HOSPITAL_WHATSAPP_ACCESS_TOKEN`, `HOSPITAL_WHATSAPP_PHONE_NUMBER_ID`,
   `HOSPITAL_WHATSAPP_TEMPLATE`, `HOSPITAL_WHATSAPP_GRAPH_VERSION`.
   No colocar estas claves en Flutter, GitHub ni documentos.
4. Desplegar `hospital-delivery`; programar su invocación por minuto mediante
   Supabase Cron/`pg_net`, usando un secreto guardado en Vault. Comprobar
   permisos de invocación, errores y reintentos. No compartir el rol de servicio
   con el programador ni con el teléfono.
5. Activar `external_delivery_enabled` solo cuando ambos canales estén
   configurados, los destinatarios sean correctos y se haya retirado cualquier
   alarma local duplicada que compita con este recorrido. La generación 14G
   (`enabled`) y el reparto por turnos (`duty_routing_enabled`) son interruptores
   independientes.

Una confirmación HTTP del proveedor acredita aceptación de la solicitud, no
lectura por la persona ni realización del cuidado. Un corte entre el envío y el
registro del resultado puede ocasionar un reintento duplicado. Falta mostrar
estado de entrega y revocación en Flutter, registrar el token FCM y ejecutar el
recorrido real con la app cerrada antes de encender los interruptores.

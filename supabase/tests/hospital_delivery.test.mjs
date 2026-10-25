import assert from "node:assert/strict";
import test from "node:test";
import { deliveryConfig, sendHospitalDelivery } from "../functions/_shared/hospital_delivery.mjs";

const config = {
  fcmProject: "test-project", waVersion: "v24.0", waPhone: "12345",
  waToken: "synthetic-token", waTemplate: "hospital_alert",
};

test("provider configuration stays disabled until both services are configured", () => {
  assert.equal(deliveryConfig(() => undefined), null);
  assert.equal(deliveryConfig((name) => ({
    HOSPITAL_FCM_PROJECT_ID: "test", HOSPITAL_FCM_CLIENT_EMAIL: "service@example.test",
    HOSPITAL_FCM_PRIVATE_KEY: "synthetic", HOSPITAL_WHATSAPP_ACCESS_TOKEN: "synthetic",
    HOSPITAL_WHATSAPP_PHONE_NUMBER_ID: "12345", HOSPITAL_WHATSAPP_TEMPLATE: "hospital_alert",
    HOSPITAL_WHATSAPP_GRAPH_VERSION: "v24.0",
  })[name])?.waTemplate, "hospital_alert");
});

test("FCM sends only a generic notice and checks provider acknowledgement", async () => {
  let body;
  const reference = await sendHospitalDelivery(
    { channel: "fcm", destination: "synthetic.device~token_123456" }, config,
    async () => "synthetic-access-token",
    async (_url, options) => {
      body = JSON.parse(options.body);
      assert.equal(options.headers.Authorization, "Bearer synthetic-access-token");
      return { ok: true, json: async () => ({ name: "projects/test/messages/1" }) };
    },
  );
  assert.equal(reference, "projects/test/messages/1");
  assert.deepEqual(Object.keys(body.message), ["token", "notification", "data"]);
  assert.ok(!JSON.stringify(body).includes("patient"));
});

test("WhatsApp uses a template without patient details or free text", async () => {
  let body;
  await sendHospitalDelivery(
    { channel: "whatsapp", destination: "+5213312345678" }, config,
    undefined,
    async (_url, options) => {
      body = JSON.parse(options.body);
      return { ok: true, json: async () => ({ messages: [{ id: "wamid.synthetic" }] }) };
    },
  );
  assert.equal(body.to, "5213312345678");
  assert.deepEqual(body.template, { name: "hospital_alert", language: { code: "es_MX" } });
  assert.equal(body.text, undefined);
});

test("provider failure does not count as delivery", async () => {
  await assert.rejects(
    sendHospitalDelivery(
      { channel: "whatsapp", destination: "+5213312345678" }, config,
      undefined, async () => ({ ok: false }),
    ),
    /provider_http_error/,
  );
});

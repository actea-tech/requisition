// Triggered by the email_outbox AFTER INSERT trigger (see migration
// 0006_email_outbox_and_templates.sql) via pg_net, authenticated with the
// service role key stored in Vault. Renders the requested template and
// sends it through Resend, then writes the result back onto the outbox row.
import { createClient } from "npm:@supabase/supabase-js@2";
import { renderTemplate, wrapEmailHtml } from "./template.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL") ?? "ACTEA Requisitions <onboarding@resend.dev>";

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let outboxId: string | undefined;
  try {
    ({ outbox_id: outboxId } = await req.json());
  } catch {
    return new Response("Invalid JSON body", { status: 400 });
  }

  if (!outboxId) {
    return new Response("outbox_id is required", { status: 400 });
  }

  const { data: outbox, error: outboxError } = await supabase
    .from("email_outbox")
    .select("id, template_key, to_emails, cc_emails, payload, status, attempts")
    .eq("id", outboxId)
    .single();

  if (outboxError || !outbox) {
    return new Response(`Outbox row not found: ${outboxError?.message ?? outboxId}`, { status: 404 });
  }

  if (outbox.status === "sent") {
    return new Response("Already sent", { status: 200 });
  }

  const nextAttempts = outbox.attempts + 1;

  if (!outbox.to_emails || outbox.to_emails.length === 0) {
    await supabase
      .from("email_outbox")
      .update({ status: "failed", error: "no recipients", attempts: nextAttempts })
      .eq("id", outboxId);
    return new Response("No recipients", { status: 200 });
  }

  const { data: template, error: templateError } = await supabase
    .from("email_templates")
    .select("subject, html_body")
    .eq("key", outbox.template_key)
    .single();

  if (templateError || !template) {
    await supabase
      .from("email_outbox")
      .update({ status: "failed", error: `template not found: ${outbox.template_key}`, attempts: nextAttempts })
      .eq("id", outboxId);
    return new Response(`Template not found: ${outbox.template_key}`, { status: 404 });
  }

  const { data: appUrlSetting } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "app_url")
    .single();
  const appUrl = appUrlSetting?.value ?? SUPABASE_URL;

  const payload = outbox.payload ?? {};
  const subject = renderTemplate(template.subject, payload);
  const bodyHtml = renderTemplate(template.html_body, payload);
  const html = wrapEmailHtml({
    title: subject,
    bodyHtml,
    logoUrl: `${appUrl}/actea-logo.png`,
    appUrl,
  });

  if (!RESEND_API_KEY) {
    await supabase
      .from("email_outbox")
      .update({ status: "failed", error: "RESEND_API_KEY not configured", attempts: nextAttempts })
      .eq("id", outboxId);
    return new Response("RESEND_API_KEY not configured", { status: 500 });
  }

  try {
    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: RESEND_FROM_EMAIL,
        to: outbox.to_emails,
        cc: outbox.cc_emails?.length ? outbox.cc_emails : undefined,
        subject,
        html,
      }),
    });

    if (!resendResponse.ok) {
      const errorBody = await resendResponse.text();
      await supabase
        .from("email_outbox")
        .update({ status: "failed", error: `Resend ${resendResponse.status}: ${errorBody}`, attempts: nextAttempts })
        .eq("id", outboxId);
      return new Response(`Resend error: ${errorBody}`, { status: 502 });
    }

    await supabase
      .from("email_outbox")
      .update({ status: "sent", sent_at: new Date().toISOString(), attempts: nextAttempts })
      .eq("id", outboxId);

    return new Response("sent", { status: 200 });
  } catch (err) {
    await supabase
      .from("email_outbox")
      .update({ status: "failed", error: String(err), attempts: nextAttempts })
      .eq("id", outboxId);
    return new Response(`Send failed: ${err}`, { status: 500 });
  }
});

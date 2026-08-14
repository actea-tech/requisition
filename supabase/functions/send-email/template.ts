// Minimal mustache-lite renderer: {{var}} substitution (HTML-escaped) and
// single-level {{#var}}...{{/var}} truthy sections. That's all our
// templates need — no partials, no loops, no nesting.

export type TemplatePayload = Record<string, unknown>;

function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function isTruthy(value: unknown): boolean {
  return value !== null && value !== undefined && value !== "" && value !== false;
}

export function renderTemplate(source: string, payload: TemplatePayload): string {
  // Sections first: {{#key}}...{{/key}}
  let out = source.replace(
    /\{\{#(\w+)\}\}([\s\S]*?)\{\{\/\1\}\}/g,
    (_match, key: string, inner: string) => (isTruthy(payload[key]) ? inner : ""),
  );

  // Then simple substitutions: {{key}}
  out = out.replace(/\{\{(\w+)\}\}/g, (_match, key: string) => escapeHtml(payload[key]));

  return out;
}

const BRAND = {
  blue: "#1E49BA",
  text: "#1F2430",
  muted: "#6B7280",
  border: "#E5E7EB",
  bg: "#F4F6FB",
};

export function wrapEmailHtml(opts: { title: string; bodyHtml: string; logoUrl: string; appUrl: string }): string {
  // Templates author buttons as `class="btn"` for readability in the DB;
  // inline the style here since many email clients strip <style> blocks.
  const body = opts.bodyHtml
    .replace(
      /class="btn"/g,
      `style="background:${BRAND.blue};color:#ffffff;padding:10px 22px;border-radius:6px;text-decoration:none;display:inline-block;font-weight:600;font-family:Arial,sans-serif;"`,
    )
    .replace(
      /<blockquote>/g,
      `<blockquote style="margin:12px 0;padding:10px 14px;border-left:3px solid ${BRAND.border};color:${BRAND.muted};background:${BRAND.bg};border-radius:4px;">`,
    );

  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:${BRAND.bg};font-family:Arial,Helvetica,sans-serif;color:${BRAND.text};">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND.bg};padding:32px 0;">
      <tr>
        <td align="center">
          <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:10px;border:1px solid ${BRAND.border};overflow:hidden;">
            <tr>
              <td style="padding:24px 32px;border-bottom:1px solid ${BRAND.border};">
                <table role="presentation" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="vertical-align:middle;">
                      <img src="${opts.logoUrl}" alt="ACTEA" height="40" style="height:40px;display:block;" />
                    </td>
                    <td style="vertical-align:middle;padding-left:12px;">
                      <span style="font-size:20px;font-weight:700;color:${BRAND.blue};font-family:Arial,sans-serif;letter-spacing:0.5px;">ACTEA</span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:28px 32px;font-size:14px;line-height:1.6;">
                ${body}
              </td>
            </tr>
            <tr>
              <td style="padding:20px 32px;border-top:1px solid ${BRAND.border};font-size:12px;color:${BRAND.muted};">
                <a href="${opts.appUrl}/login" style="color:${BRAND.muted};text-decoration:underline;">ACTEA Requisitions</a>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

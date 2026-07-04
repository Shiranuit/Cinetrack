//! HTML + plain-text bodies for transactional emails. Email-client-safe: table
//! layout with inline styles only, and every HTML mail ships a plain-text
//! alternative. Each builder returns `(subject, text, html)`.

/// Cinetrack brand accent (matches the app's gold primary).
const ACCENT: &str = "#f4b740";

/// Shared dark card layout with a call-to-action button and a copy-paste link.
fn layout(title: &str, intro: &str, button_label: &str, link: &str, note: &str) -> String {
    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0f1216;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0f1216;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background:#171b21;border-radius:14px;">
        <tr><td style="padding:28px 32px 4px 32px;">
          <div style="font-size:20px;font-weight:700;letter-spacing:1.5px;color:#ffffff;">CINE<span style="color:{accent};">TRACK</span></div>
        </td></tr>
        <tr><td style="padding:12px 32px 0 32px;">
          <h1 style="margin:0 0 12px 0;font-size:22px;color:#ffffff;font-weight:600;">{title}</h1>
          <p style="margin:0 0 24px 0;font-size:15px;line-height:1.55;color:#b8c0cc;">{intro}</p>
          <a href="{link}" style="display:inline-block;background:{accent};color:#1a1400;text-decoration:none;font-weight:600;font-size:15px;padding:13px 26px;border-radius:10px;">{button_label}</a>
          <p style="margin:24px 0 0 0;font-size:13px;line-height:1.5;color:#7a8494;">{note}</p>
          <p style="margin:16px 0 0 0;font-size:12px;line-height:1.5;color:#5a6472;">Or paste this link into your browser:<br><span style="color:#8a94a4;word-break:break-all;">{link}</span></p>
        </td></tr>
        <tr><td style="padding:24px 32px 28px 32px;">
          <hr style="border:none;border-top:1px solid #242a32;margin:0 0 16px 0;">
          <p style="margin:0;font-size:12px;color:#5a6472;">Cinetrack — track every show, film and rewatch.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>"#,
        accent = ACCENT,
        title = title,
        intro = intro,
        link = link,
        button_label = button_label,
        note = note,
    )
}

/// Password-reset email. `link` is the frontend reset URL (valid 10 minutes).
pub fn reset_password(link: &str) -> (String, String, String) {
    let subject = "Reset your Cinetrack password".to_string();
    let text = format!(
        "Reset your Cinetrack password\n\n\
         We received a request to reset your password. Open the link below to choose a \
         new one (valid for 10 minutes):\n\n{link}\n\n\
         If you didn't request this, you can safely ignore this email — your password \
         won't change."
    );
    let html = layout(
        "Reset your password",
        "We received a request to reset your Cinetrack password. Use the button below to \
         choose a new one — this link is valid for 10 minutes.",
        "Reset password",
        link,
        "If you didn't request this, you can safely ignore this email — your password won't change.",
    );
    (subject, text, html)
}

/// Invitation email. `link` is the frontend sign-up URL carrying the one-time code.
pub fn invite(link: &str) -> (String, String, String) {
    let subject = "Your Cinetrack invitation".to_string();
    let text = format!(
        "You've been invited to Cinetrack\n\n\
         Create your account with the link below (valid for 14 days, single use):\n\n{link}\n\n\
         If you weren't expecting this, you can ignore it."
    );
    let html = layout(
        "You're invited to Cinetrack",
        "Someone invited you to join Cinetrack — track every show, film and rewatch. Create \
         your account with the button below. This invitation is valid for 14 days and can be \
         used once.",
        "Create your account",
        link,
        "If you weren't expecting this invitation, you can safely ignore it.",
    );
    (subject, text, html)
}

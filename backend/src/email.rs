//! Transactional email over SMTP (via lettre). When SMTP is not configured the
//! mailer LOGS the message instead of sending it, so dev works without a mail
//! server and a mail outage never breaks signup/reset flows.

use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
    message::{MultiPart, header::ContentType},
    transport::smtp::authentication::Credentials,
};

use crate::config::SmtpConfig;

#[derive(Clone)]
pub struct Mailer {
    inner: Option<Inner>,
}

#[derive(Clone)]
struct Inner {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from: String,
}

impl Mailer {
    pub fn from_config(smtp: Option<&SmtpConfig>) -> Self {
        let inner = smtp.and_then(|c| {
            // STARTTLS relay for external providers; plain (no encryption) for a
            // trusted relay on the private network (`SMTP_TLS=none`) — the internal
            // Postfix in prod, or Mailpit in dev.
            let builder = if c.starttls {
                match AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&c.host) {
                    Ok(b) => b,
                    Err(e) => {
                        tracing::error!("email: invalid SMTP config: {e}");
                        return None;
                    }
                }
            } else {
                AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&c.host)
            };
            let mut builder = builder.port(c.port);
            // Only authenticate when a username is set (internal relays don't need it).
            if !c.username.is_empty() {
                builder = builder.credentials(Credentials::new(c.username.clone(), c.password.clone()));
            }
            Some(Inner { transport: builder.build(), from: c.from.clone() })
        });
        if inner.is_none() {
            tracing::warn!("email: SMTP not configured — emails will be logged, not sent");
        }
        Mailer { inner }
    }

    /// Send a plain-text email. Best-effort: never returns an error, so a mail
    /// failure can't break the caller (which already returns a generic response
    /// to avoid account enumeration). Failures are logged.
    pub async fn send(&self, to: &str, subject: &str, body: &str) {
        self.deliver(to, subject, body, None).await;
    }

    /// Send an HTML email with a plain-text fallback (a `multipart/alternative` so
    /// text-only clients still get a readable message). Same best-effort semantics.
    pub async fn send_html(&self, to: &str, subject: &str, text: &str, html: &str) {
        self.deliver(to, subject, text, Some(html)).await;
    }

    async fn deliver(&self, to: &str, subject: &str, text: &str, html: Option<&str>) {
        let Some(inner) = &self.inner else {
            tracing::info!("email (unsent — no SMTP) to={to} subject={subject:?}\n{text}");
            return;
        };
        let from = match inner.from.parse() {
            Ok(m) => m,
            Err(e) => {
                tracing::error!("email: invalid MAIL_FROM {:?}: {e}", inner.from);
                return;
            }
        };
        let to_mbox = match to.parse() {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("email: invalid recipient {to:?}: {e}");
                return;
            }
        };
        let builder = Message::builder().from(from).to(to_mbox).subject(subject);
        let msg = match html {
            Some(html) => builder.multipart(MultiPart::alternative_plain_html(
                text.to_string(),
                html.to_string(),
            )),
            None => builder.header(ContentType::TEXT_PLAIN).body(text.to_string()),
        };
        let msg = match msg {
            Ok(m) => m,
            Err(e) => {
                tracing::error!("email: build failed: {e}");
                return;
            }
        };
        if let Err(e) = inner.transport.send(msg).await {
            tracing::error!("email: send to {to} failed: {e}");
        }
    }
}

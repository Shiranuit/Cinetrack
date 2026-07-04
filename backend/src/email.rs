//! Transactional email over SMTP (via lettre). When SMTP is not configured the
//! mailer LOGS the message instead of sending it, so dev works without a mail
//! server and a mail outage never breaks signup/reset flows.

use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
    message::header::ContentType, transport::smtp::authentication::Credentials,
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
            match AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&c.host) {
                Ok(builder) => Some(Inner {
                    transport: builder
                        .port(c.port)
                        .credentials(Credentials::new(c.username.clone(), c.password.clone()))
                        .build(),
                    from: c.from.clone(),
                }),
                Err(e) => {
                    tracing::error!("email: invalid SMTP config: {e}");
                    None
                }
            }
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
        let Some(inner) = &self.inner else {
            tracing::info!("email (unsent — no SMTP) to={to} subject={subject:?}\n{body}");
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
        let msg = match Message::builder()
            .from(from)
            .to(to_mbox)
            .subject(subject)
            .header(ContentType::TEXT_PLAIN)
            .body(body.to_string())
        {
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

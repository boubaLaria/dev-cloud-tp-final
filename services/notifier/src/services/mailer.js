'use strict';
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'mailhog',
  port: parseInt(process.env.SMTP_PORT || '1025', 10),
  secure: false,
  tls: { rejectUnauthorized: false }
});

async function sendNotification(parcel) {
  const info = await transporter.sendMail({
    from: '"GreenLogistics" <notifications@greenlogistics.local>',
    to: parcel.recipient_email,
    subject: `[GreenLogistics] Votre colis ${parcel.tracking_code} arrive dans ~5 min`,
    text: [
      `Bonjour ${parcel.recipient_name},`,
      '',
      `Votre livreur est à moins de 2 km de votre adresse.`,
      `Votre colis ${parcel.tracking_code} sera livré dans environ 5 minutes.`,
      '',
      'Merci de votre confiance,',
      "L'équipe GreenLogistics"
    ].join('\n')
  });

  console.log(`[notifier] Email envoyé à ${parcel.recipient_email} — messageId: ${info.messageId}`);
  return info;
}

module.exports = { sendNotification };

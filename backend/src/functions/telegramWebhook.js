const { ok, parseBody } = require('../lib/http');
const { getEvent, getTicketByTelegramLinkCode, linkTelegramChat } = require('../lib/db');
const { generateQrPngBuffer } = require('../lib/qrcode');
const { webhookSecret, sendMessage, sendPhoto, escapeHtml } = require('../lib/telegram');

const HELP_TEXT =
  'Hi! I deliver your EventPass tickets.\n\n' +
  'Open the <b>Get ticket on Telegram</b> link in your ticket email and your QR code will appear here. ' +
  'You will also get a message when your ticket is scanned at the gate.';

exports.handler = async (event) => {
  const headers = event.headers || {};
  const secretHeader =
    headers['X-Telegram-Bot-Api-Secret-Token'] || headers['x-telegram-bot-api-secret-token'];
  if (secretHeader !== webhookSecret()) {
    return ok(401, { message: 'Unauthorized' });
  }

  try {
    const update = parseBody(event);
    const message = update.message;
    if (!message || !message.chat || typeof message.text !== 'string') {
      return ok(200, { ok: true });
    }

    const chatId = message.chat.id;
    const [command, linkCode] = message.text.trim().split(/\s+/);

    if (command !== '/start' || !linkCode) {
      await sendMessage(chatId, HELP_TEXT);
      return ok(200, { ok: true });
    }

    const ticket = await getTicketByTelegramLinkCode(linkCode);
    if (!ticket) {
      await sendMessage(chatId, 'This ticket link is invalid or has already been used.');
      return ok(200, { ok: true });
    }
    if (ticket.status === 'CANCELLED') {
      await sendMessage(chatId, 'This ticket has been cancelled.');
      return ok(200, { ok: true });
    }

    // One-time link: the conditional update consumes the code, so a forwarded
    // link can't be used to pull the same QR into a second chat.
    try {
      await linkTelegramChat(ticket.ticketId, chatId, linkCode);
    } catch (condErr) {
      if (condErr.name === 'ConditionalCheckFailedException') {
        await sendMessage(chatId, 'This ticket link has already been used.');
        return ok(200, { ok: true });
      }
      throw condErr;
    }

    const eventRecord = await getEvent(ticket.eventId);
    const qrBuffer = await generateQrPngBuffer(ticket.qrToken);
    const caption = [
      `🎟 <b>${escapeHtml(eventRecord ? eventRecord.name : 'Your event')}</b>`,
      eventRecord ? `${escapeHtml(eventRecord.date)}${eventRecord.venue ? ` · ${escapeHtml(eventRecord.venue)}` : ''}` : '',
      `Ticket ID: <code>${escapeHtml(ticket.ticketId)}</code>`,
      '',
      'Show this QR code at the gate. It is single-use, so don\'t share it.',
    ].join('\n');

    await sendPhoto(chatId, qrBuffer, caption);
    return ok(200, { ok: true });
  } catch (err) {
    // Always 200 so Telegram doesn't retry the same update forever
    console.error('telegramWebhook error', err);
    return ok(200, { ok: true });
  }
};

const { createHash, randomBytes } = require('crypto');

const API_BASE = 'https://api.telegram.org';

function isTelegramEnabled() {
  return Boolean(process.env.TELEGRAM_BOT_TOKEN && process.env.TELEGRAM_BOT_USERNAME);
}

// One-time code embedded in the t.me deep link (Telegram allows up to 64 chars of [A-Za-z0-9_-])
function generateLinkCode() {
  return randomBytes(16).toString('hex');
}

function buildDeepLink(linkCode) {
  return `https://t.me/${process.env.TELEGRAM_BOT_USERNAME}?start=${linkCode}`;
}

// Derived from the bot token so no extra secret has to be managed; Telegram sends it back
// in the X-Telegram-Bot-Api-Secret-Token header on every webhook call.
function webhookSecret() {
  return createHash('sha256').update(process.env.TELEGRAM_BOT_TOKEN || '').digest('hex').slice(0, 48);
}

async function callTelegram(method, body) {
  const isForm = body instanceof FormData;
  const response = await fetch(`${API_BASE}/bot${process.env.TELEGRAM_BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: isForm ? undefined : { 'Content-Type': 'application/json' },
    body: isForm ? body : JSON.stringify(body),
  });
  const result = await response.json();
  if (!result.ok) {
    throw new Error(`Telegram ${method} failed: ${result.description || response.status}`);
  }
  return result.result;
}

async function sendMessage(chatId, text) {
  return callTelegram('sendMessage', { chat_id: chatId, text, parse_mode: 'HTML' });
}

async function sendPhoto(chatId, pngBuffer, caption) {
  const form = new FormData();
  form.append('chat_id', String(chatId));
  form.append('caption', caption);
  form.append('parse_mode', 'HTML');
  form.append('photo', new Blob([pngBuffer], { type: 'image/png' }), 'ticket-qr.png');
  return callTelegram('sendPhoto', form);
}

// Escape user-controlled values for Telegram's HTML parse mode
const escapeHtml = (value) =>
  String(value || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

module.exports = {
  isTelegramEnabled,
  generateLinkCode,
  buildDeepLink,
  webhookSecret,
  sendMessage,
  sendPhoto,
  escapeHtml,
};

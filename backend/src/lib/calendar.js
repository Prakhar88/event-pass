// Default event length when only a start time is known
const DEFAULT_DURATION_MS = 3 * 60 * 60 * 1000;

// RFC 5545 text escaping
const escapeText = (value) =>
  String(value || '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');

// 2026-10-25T12:30:00.000Z -> 20261025T123000Z
const toIcsDate = (date) => date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

// Lines longer than 75 octets must be folded (continuation lines start with a space)
const fold = (line) => {
  const parts = [];
  for (let i = 0; i < line.length; i += 73) parts.push(line.slice(i, i + 73));
  return parts.join('\r\n ');
};

/**
 * Build an iCalendar (.ics) invite for a ticket.
 * Returns null when the event date can't be parsed, so the email still goes out without it.
 *
 * @param {object} opts
 * @param {string} opts.ticketId
 * @param {string} opts.eventName
 * @param {string} opts.eventDate - ISO date string
 * @param {string} [opts.venue]
 * @param {string} [opts.description]
 */
function buildTicketIcs({ ticketId, eventName, eventDate, venue, description }) {
  const start = new Date(eventDate);
  if (isNaN(start.getTime())) return null;
  const end = new Date(start.getTime() + DEFAULT_DURATION_MS);

  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//EventPass//Ticketing//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${ticketId}@eventpass`,
    `DTSTAMP:${toIcsDate(new Date())}`,
    `DTSTART:${toIcsDate(start)}`,
    `DTEND:${toIcsDate(end)}`,
    `SUMMARY:${escapeText(eventName)}`,
    ...(venue ? [`LOCATION:${escapeText(venue)}`] : []),
    `DESCRIPTION:${escapeText(description || `Ticket ID: ${ticketId}`)}`,
    'BEGIN:VALARM',
    'TRIGGER:-PT1H',
    'ACTION:DISPLAY',
    `DESCRIPTION:${escapeText(`${eventName} starts in 1 hour`)}`,
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ];

  return lines.map(fold).join('\r\n') + '\r\n';
}

module.exports = { buildTicketIcs };

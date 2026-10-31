import { createHash } from 'node:crypto';
import { loadShifterEvents } from './shifter.ts';
import { loadGoogleCalendarEvents } from './google-calendar.ts';
import type { CalendarEvent } from './types.ts';

export type CalendarProvider = 'shifter' | 'google';

export function getCalendarProvider(): CalendarProvider {
  const provider = process.env.SASHFRAME_CALENDAR_PROVIDER || 'shifter';
  if (provider !== 'shifter' && provider !== 'google') throw new Error('Unsupported calendar provider');
  return provider;
}

/** Read one snapshot, then derive its ETag from the exact response body. */
export function getCalendarSnapshot(): { events: CalendarEvent[]; etag: string; provider: CalendarProvider } {
  const provider = getCalendarProvider();
  const events = provider === 'google' ? loadGoogleCalendarEvents() : loadShifterEvents();
  const digest = createHash('sha256').update(provider).update(JSON.stringify(events)).digest('hex');
  return { events, etag: `"${digest}"`, provider };
}

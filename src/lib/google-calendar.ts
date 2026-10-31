import fs from 'node:fs';
import path from 'node:path';
import type { CalendarEvent } from './types.ts';
import { classifyShift, formatShiftTitle } from './shifter-utils.ts';

interface GoogleEvent {
  id?: string;
  status?: string;
  summary?: string;
  description?: string;
  location?: string;
  visibility?: string;
  start?: { date?: string; dateTime?: string };
  end?: { date?: string; dateTime?: string };
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 86_400_000;

function validDate(value: unknown): value is string {
  return typeof value === 'string' && DATE.test(value) &&
    !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}

function nextDate(value: string): string {
  return new Date(Date.parse(value) + DAY_MS).toISOString().slice(0, 10);
}

function localParts(value: Date, timeZone: string): { date: string; time: string } {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
  }).formatToParts(value);
  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find(p => p.type === type)!.value;
  return { date: `${get('year')}-${get('month')}-${get('day')}`, time: `${get('hour')}:${get('minute')}` };
}

/** Google expands recurring series before they enter the cache. Each instance keeps its own ID. */
export function normalizeGoogleEvents(rawEvents: unknown[], timeZone = 'Europe/London'): CalendarEvent[] {
  // Reject invalid timezone configuration even for an empty calendar.
  new Intl.DateTimeFormat('en-GB', { timeZone });
  const events = new Map<string, CalendarEvent>();
  for (const raw of rawEvents) {
    if (!raw || typeof raw !== 'object') continue;
    const item = raw as GoogleEvent;
    if (typeof item.id !== 'string' || !item.id || item.status === 'cancelled') continue;
    const privateEvent = item.visibility === 'private';
    const title = privateEvent ? 'Busy' : (typeof item.summary === 'string' && item.summary.trim() ? item.summary.trim() : 'Busy');
    const description = !privateEvent && typeof item.description === 'string' ? item.description : undefined;
    const location = !privateEvent && typeof item.location === 'string' ? item.location : undefined;
    const category = classifyShift({ _id: 0, texto: title, abreviatura: title }, description);
    // Google is also useful for ordinary appointments: do not label all appointments as shifts.
    const shiftType = category === 'other' ? undefined : category;
    const base = {
      title: shiftType ? formatShiftTitle(title, shiftType) : title,
      description, location, source: 'google', shiftType,
      badge: shiftType === 'ld' ? 'LD' : shiftType === 'day_off' ? 'Off' : shiftType === 'night' ? 'Night' : undefined
    };
    const add = (date: string, isAllDay: boolean, startTime?: string, endTime?: string) => {
      const id = `google-${item.id}-${date}`;
      events.set(id, { ...base, id, date, isAllDay, startTime, endTime });
    };

    if (validDate(item.start?.date) && validDate(item.end?.date)) {
      // Google all-day ends are exclusive. Bound expansion of malformed/unreasonable events.
      if (item.end.date <= item.start.date || Date.parse(item.end.date) - Date.parse(item.start.date) > 366 * DAY_MS) continue;
      for (let day = item.start.date; day < item.end.date; day = nextDate(day)) add(day, true);
      continue;
    }
    const startValue = item.start?.dateTime;
    const endValue = item.end?.dateTime;
    if (typeof startValue !== 'string' || typeof endValue !== 'string' ||
        !/(?:Z|[+-]\d{2}:\d{2})$/.test(startValue) || !/(?:Z|[+-]\d{2}:\d{2})$/.test(endValue)) continue;
    const start = new Date(startValue);
    const end = new Date(endValue);
    if (Number.isNaN(start.valueOf()) || Number.isNaN(end.valueOf()) || end <= start || end.valueOf() - start.valueOf() > 366 * DAY_MS) continue;
    const from = localParts(start, timeZone);
    const to = localParts(end, timeZone);
    // Preserve the existing overnight shift display: start day with its actual end time.
    if (from.date === to.date || (shiftType && end.valueOf() - start.valueOf() <= DAY_MS)) {
      add(from.date, shiftType === 'day_off', shiftType === 'day_off' ? undefined : from.time, shiftType === 'day_off' ? undefined : to.time);
      continue;
    }
    for (let day = from.date; day <= to.date; day = nextDate(day)) {
      if (day === to.date && to.time === '00:00') break;
      add(day, shiftType === 'day_off', shiftType === 'day_off' ? undefined : day === from.date ? from.time : '00:00', shiftType === 'day_off' ? undefined : day === to.date ? to.time : '24:00');
    }
  }
  return [...events.values()].sort((a, b) => a.date.localeCompare(b.date) || Number(b.isAllDay) - Number(a.isAllDay) || (a.startTime || '').localeCompare(b.startTime || '') || a.id.localeCompare(b.id));
}

const goodSnapshots = new Map<string, CalendarEvent[]>();

export function loadGoogleCalendarEvents(): CalendarEvent[] {
  const calendarId = process.env.GOOGLE_CALENDAR_ID;
  if (!calendarId || calendarId === 'primary') throw new Error('GOOGLE_CALENDAR_ID must identify the shared calendar explicitly');
  const cachePath = path.resolve(process.env.GOOGLE_CALENDAR_CACHE || 'data/calendar/google.json');
  const timeZone = process.env.SASHFRAME_TIMEZONE || 'Europe/London';
  const key = JSON.stringify([cachePath, calendarId, timeZone]);
  try {
    const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    // A provider/configuration switch must never show a different calendar's old cache.
    if (cache.calendarId !== calendarId) return [];
    if (cache.version !== 1 || !Array.isArray(cache.events)) throw new Error('Invalid Google calendar cache');
    if (cache.events.some((item: GoogleEvent) => !item || typeof item !== 'object' ||
      typeof item.id !== 'string' || !item.id ||
      (item.status !== 'cancelled' && normalizeGoogleEvents([item], timeZone).length === 0))) {
      throw new Error('Invalid Google calendar event in cache');
    }
    const events = normalizeGoogleEvents(cache.events, timeZone);
    goodSnapshots.set(key, events);
    return events;
  } catch (error) {
    const previous = goodSnapshots.get(key);
    if (previous) return previous;
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw new Error('Google calendar cache is unavailable');
  }
}

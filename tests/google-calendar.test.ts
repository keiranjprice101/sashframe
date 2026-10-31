import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { normalizeGoogleEvents, loadGoogleCalendarEvents } from '../src/lib/google-calendar.ts';
import { getCalendarProvider, getCalendarSnapshot } from '../src/lib/calendar.ts';
import { GET } from '../src/pages/api/calendar.ts';

function timed(id: string, summary: string, start: string, end: string) {
  return { id, summary, start: { dateTime: start }, end: { dateTime: end } };
}

test('Google all-day end is exclusive; each display day has a stable unique ID', () => {
  const raw = [{ id: 'holiday', summary: 'Holiday', start: { date: '2026-10-30' }, end: { date: '2026-11-02' } }];
  const events = normalizeGoogleEvents(raw);
  assert.deepEqual(events.map(e => e.date), ['2026-10-30', '2026-10-31', '2026-11-01']);
  assert.ok(events.every(e => e.isAllDay && e.source === 'google'));
  assert.equal(new Set(events.map(e => e.id)).size, 3);
  assert.deepEqual(normalizeGoogleEvents(raw), events);
});

test('Google times use the appliance timezone across BST/GMT and overnight shifts stay on their start day', () => {
  const events = normalizeGoogleEvents([
    timed('summer', 'Appointment', '2026-07-01T08:00:00Z', '2026-07-01T09:00:00Z'),
    timed('winter', 'Appointment', '2026-11-01T08:00:00Z', '2026-11-01T09:00:00Z'),
    timed('night', 'Nurse N', '2026-10-24T21:00:00+01:00', '2026-10-25T07:00:00Z')
  ]);
  assert.equal(events.find(e => e.id.includes('summer'))?.startTime, '09:00');
  assert.equal(events.find(e => e.id.includes('winter'))?.startTime, '08:00');
  const night = events.find(e => e.shiftType === 'night')!;
  assert.equal(night.date, '2026-10-24');
  assert.equal(night.startTime, '21:00');
  assert.equal(night.endTime, '07:00');
  assert.equal(events.length, 3);
});

test('Google shift categories match Shifter; ordinary events retain their titles and generic styling', () => {
  const events = normalizeGoogleEvents(['Nurse LD', 'Day Off', 'School visit'].map((summary, index) => ({
    id: String(index), summary, start: { date: '2026-10-30' }, end: { date: '2026-10-31' }
  })));
  assert.equal(events[0].shiftType, 'ld');
  assert.equal(events[1].shiftType, 'day_off');
  assert.equal(events[2].shiftType, undefined);
  assert.equal(events[2].title, 'School visit');
});

test('Multi-day timed events include each occupied day and exclude midnight on the end day', () => {
  const events = normalizeGoogleEvents([timed('trip', 'Trip', '2026-11-01T12:00:00Z', '2026-11-04T00:00:00Z')]);
  assert.deepEqual(events.map(e => [e.date, e.startTime, e.endTime]), [
    ['2026-11-01', '12:00', '24:00'], ['2026-11-02', '00:00', '24:00'], ['2026-11-03', '00:00', '24:00']
  ]);
});

test('Ordinary appointments crossing midnight appear on both occupied days', () => {
  const events = normalizeGoogleEvents([timed('appointment', 'Travel', '2026-11-01T23:00:00Z', '2026-11-02T01:00:00Z')]);
  assert.deepEqual(events.map(e => [e.date, e.startTime, e.endTime]), [
    ['2026-11-01', '23:00', '24:00'], ['2026-11-02', '00:00', '01:00']
  ]);
});

test('Cancelled recurring instances are removed and distinct occurrences remain distinct', () => {
  const events = normalizeGoogleEvents([
    timed('series_20261101', 'Meeting', '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z'),
    { ...timed('series_20261108', 'Meeting', '2026-11-08T10:00:00Z', '2026-11-08T11:00:00Z'), status: 'cancelled' },
    timed('series_20261115', 'Moved meeting', '2026-11-16T10:00:00Z', '2026-11-16T11:00:00Z')
  ]);
  assert.deepEqual(events.map(e => e.date), ['2026-11-01', '2026-11-16']);
  assert.equal(new Set(events.map(e => e.id)).size, 2);
});

test('Private event details stay private; malformed and impossible dates are ignored', () => {
  const events = normalizeGoogleEvents([
    { ...timed('private', 'Sensitive title', '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z'), visibility: 'private', description: 'Sensitive description', location: 'Sensitive address' },
    { id: 'bad', start: { date: '2026-02-30' }, end: { date: '2026-03-02' } },
    timed('bad-time', 'Bad', '2026-11-01T10:00:00', '2026-11-01T11:00:00'),
    timed('reverse', 'Bad', '2026-11-01T12:00:00Z', '2026-11-01T11:00:00Z'),
    null
  ]);
  assert.equal(events.length, 1);
  assert.equal(events[0].title, 'Busy');
  assert.equal(events[0].description, undefined);
  assert.equal(events[0].location, undefined);
  assert.throws(() => normalizeGoogleEvents([], 'invalid/timezone'));
});

test('Provider selection, cache isolation, last-good snapshots, and ETags use exact response content', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'sashframe-google-'));
  const cachePath = path.join(directory, 'google.json');
  const keys = ['SASHFRAME_CALENDAR_PROVIDER', 'GOOGLE_CALENDAR_ID', 'GOOGLE_CALENDAR_CACHE', 'SASHFRAME_TIMEZONE'];
  const before = Object.fromEntries(keys.map(key => [key, process.env[key]]));
  const snapshot = { version: 1, calendarId: 'test-calendar', events: [timed('one', 'Meeting', '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z')] };
  try {
    delete process.env.SASHFRAME_CALENDAR_PROVIDER;
    assert.equal(getCalendarProvider(), 'shifter');
    process.env.SASHFRAME_CALENDAR_PROVIDER = 'unsupported';
    assert.throws(getCalendarProvider);
    process.env.SASHFRAME_CALENDAR_PROVIDER = 'google';
    process.env.GOOGLE_CALENDAR_CACHE = cachePath;
    process.env.GOOGLE_CALENDAR_ID = 'test-calendar';
    process.env.SASHFRAME_TIMEZONE = 'Europe/London';
    assert.deepEqual(loadGoogleCalendarEvents(), []);
    fs.writeFileSync(cachePath, JSON.stringify(snapshot));
    const loaded = getCalendarSnapshot();
    assert.equal(loaded.events.length, 1);
    const response = await GET({ request: new Request('http://localhost/api/calendar') } as any);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('etag'), loaded.etag);
    assert.deepEqual(await response.json(), JSON.parse(JSON.stringify(loaded.events)));
    const unchanged = await GET({ request: new Request('http://localhost/api/calendar', { headers: { 'If-None-Match': loaded.etag } }) } as any);
    assert.equal(unchanged.status, 304);
    fs.writeFileSync(cachePath, JSON.stringify({ ...snapshot, syncedAt: 'a different timestamp' }));
    assert.equal(getCalendarSnapshot().etag, loaded.etag);
    fs.writeFileSync(cachePath, '{invalid');
    assert.deepEqual(getCalendarSnapshot(), loaded);
    fs.writeFileSync(cachePath, JSON.stringify({ ...snapshot, events: [null] }));
    assert.deepEqual(getCalendarSnapshot(), loaded);
    process.env.GOOGLE_CALENDAR_ID = 'another-calendar';
    assert.deepEqual(loadGoogleCalendarEvents(), []);
    fs.writeFileSync(cachePath, '{invalid');
    assert.throws(loadGoogleCalendarEvents);
    fs.writeFileSync(cachePath, JSON.stringify(snapshot));
    assert.deepEqual(loadGoogleCalendarEvents(), []);
    process.env.GOOGLE_CALENDAR_ID = 'test-calendar';
    fs.writeFileSync(cachePath, JSON.stringify({ ...snapshot, events: [] }));
    const empty = getCalendarSnapshot();
    assert.deepEqual(empty.events, []);
    assert.notEqual(empty.etag, loaded.etag);
    process.env.GOOGLE_CALENDAR_ID = 'primary';
    assert.equal((await GET({ request: new Request('http://localhost/api/calendar') } as any)).status, 503);
  } finally {
    for (const key of keys) {
      if (before[key] === undefined) delete process.env[key];
      else process.env[key] = before[key];
    }
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

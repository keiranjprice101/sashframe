import test from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import type { CalendarEvent } from '../src/lib/types.ts';
import {
  parseShifterFecha,
  classifyShift,
  parseShifterFile,
  getDayShiftType,
  getShiftAccentColor,
  poolEvents,
  loadShifterEvents,
  sortEvents,
  getShifterFingerprint,
  clearShifterCache
} from '../src/lib/shifter.ts';
import { GET as getCalendarApi } from '../src/pages/api/calendar.ts';

test('1. parseShifterFecha: Correct zero-indexed month conversion and date validation', () => {
  // Test prompt example: 20261008 represents 8 November 2026 rather than 8 October 2026
  assert.strictEqual(parseShifterFecha(20261008), '2026-11-08');

  // Month 00 = January
  assert.strictEqual(parseShifterFecha(20210001), '2021-01-01');

  // Month 01 = February (e.g. Valentine's Day)
  assert.strictEqual(parseShifterFecha(20210114), '2021-02-14');

  // Month 09 = October (e.g. Halloween 31 October)
  assert.strictEqual(parseShifterFecha(20260931), '2026-10-31');

  // Month 11 = December (e.g. 12 December)
  assert.strictEqual(parseShifterFecha(20261112), '2026-12-12');

  // Leap year: 2024 is a leap year, 29 Feb is valid
  assert.strictEqual(parseShifterFecha(20240129), '2024-02-29');

  // Non-leap year: 2023 Feb 29 is invalid
  assert.strictEqual(parseShifterFecha(20230129), null);

  // 31 April does not exist (April has 30 days)
  assert.strictEqual(parseShifterFecha(20260331), null);

  // Month 12 is out of range for 0-indexed months (valid are 00-11)
  assert.strictEqual(parseShifterFecha(20261201), null);

  // Invalid inputs
  assert.strictEqual(parseShifterFecha(null), null);
  assert.strictEqual(parseShifterFecha(undefined), null);
  assert.strictEqual(parseShifterFecha(12345), null);
  assert.strictEqual(parseShifterFecha('invalid'), null);
});

test('2. classifyShift: Mapping LD, Day Off, Night, and Other shifts', () => {
  // LD mappings
  assert.strictEqual(classifyShift({ _id: 3, texto: 'Nurse LD', abreviatura: 'Nurse LD' }), 'ld');
  assert.strictEqual(classifyShift({ _id: 10, texto: 'ld', abreviatura: 'LD' }), 'ld');
  assert.strictEqual(classifyShift({ _id: 11, texto: 'Long Day', abreviatura: 'Long' }), 'ld');

  // Day Off mappings
  assert.strictEqual(classifyShift({ _id: 1, texto: 'day off', abreviatura: 'day off' }), 'day_off');
  assert.strictEqual(classifyShift({ _id: 12, texto: 'Day Off', abreviatura: 'Off' }), 'day_off');
  assert.strictEqual(classifyShift({ _id: 13, texto: 'OFF', abreviatura: 'off' }), 'day_off');

  // Night mappings
  assert.strictEqual(classifyShift({ _id: 6, texto: 'Nurse N', abreviatura: 'Nurse N' }), 'night');
  assert.strictEqual(classifyShift({ _id: 14, texto: 'Night shift', abreviatura: 'Night' }), 'night');
  assert.strictEqual(classifyShift({ _id: 15, texto: 'Nights', abreviatura: 'n' }), 'night');

  // Contextual LD indicator via notes (e.g. nurse in charge with LD in notes)
  assert.strictEqual(classifyShift({ _id: 4, texto: 'nurse in charge ', abreviatura: 'in charge' }, 'LD'), 'ld');
  assert.strictEqual(classifyShift({ _id: 4, texto: 'nurse in charge ', abreviatura: 'in charge' }, 'LD\nMeeting'), 'ld');

  // Other non-canonical shifts
  assert.strictEqual(classifyShift({ _id: 2, texto: 'study day ', abreviatura: 'study day' }), 'other');
  assert.strictEqual(classifyShift({ _id: 5, texto: 'sick', abreviatura: 'sick' }), 'other');
  assert.strictEqual(classifyShift({ _id: 7, texto: 'dorrel', abreviatura: 'dorrel' }), 'other');
  assert.strictEqual(classifyShift({ _id: 8, texto: 'Maple', abreviatura: 'maple' }), 'other');
  assert.strictEqual(classifyShift({ _id: 99, texto: 'Training meeting', abreviatura: 'train' }), 'other');

  // Null definition fallback
  assert.strictEqual(classifyShift(null, null), 'other');
});

test('3. Handling unrecognised or missing shift definitions gracefully', () => {
  // Create an in-memory SQLite database to test edge cases
  const tempDbPath = path.resolve('tests/temp_test.sqlite');
  if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);

  const db = new DatabaseSync(tempDbPath);
  db.exec(`
    CREATE TABLE tablaTurnos (_id INTEGER PRIMARY KEY, texto TEXT, abreviatura TEXT, horaInicio1 TEXT, horaFinal1 TEXT);
    CREATE TABLE dias (fecha INTEGER PRIMARY KEY, turno1 INTEGER, turno2 INTEGER, notas TEXT);
    
    -- Only shift 1 is defined
    INSERT INTO tablaTurnos (_id, texto, abreviatura, horaInicio1, horaFinal1) VALUES (1, 'day off', 'day off', '08:00', '14:00');
    
    -- Day referencing missing shift ID 999
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260908, 999, 0, 'Testing unrecognised shift');
    
    -- Day referencing missing secondary shift ID 888
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260909, 1, 888, '');
  `);
  db.close();

  try {
    const events = parseShifterFile(tempDbPath);
    assert.strictEqual(events.length >= 2, true);

    // Event with unknown shift 999 should have fallback title and 'other' type
    const unrecognisedEvent = events.find(e => e.id.includes('-t1-999'));
    assert.ok(unrecognisedEvent);
    assert.strictEqual(unrecognisedEvent.title, 'Shift #999');
    assert.strictEqual(unrecognisedEvent.shiftType, 'other');

    // Event with known shift 1 and unknown shift 888
    const knownEvent = events.find(e => e.id.includes('-t1-1'));
    assert.ok(knownEvent);
    assert.strictEqual(knownEvent.title, 'Day Off');
    assert.strictEqual(knownEvent.shiftType, 'day_off');

    const unrecognisedSecondary = events.find(e => e.id.includes('-t2-888'));
    assert.ok(unrecognisedSecondary);
    assert.strictEqual(unrecognisedSecondary.title, 'Shift #888');
    assert.strictEqual(unrecognisedSecondary.shiftType, 'other');
  } finally {
    if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);
  }
});

test('4. Handling dates without assigned shifts (empty shifts vs notes only)', () => {
  const tempDbPath = path.resolve('tests/temp_empty_shifts.sqlite');
  if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);

  const db = new DatabaseSync(tempDbPath);
  db.exec(`
    CREATE TABLE tablaTurnos (_id INTEGER PRIMARY KEY, texto TEXT, abreviatura TEXT, horaInicio1 TEXT, horaFinal1 TEXT);
    CREATE TABLE dias (fecha INTEGER PRIMARY KEY, turno1 INTEGER, turno2 INTEGER, notas TEXT);
    
    -- 1. Date with 0 shifts and empty notes
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260901, 0, 0, '');
    
    -- 2. Date with 0 shifts and null notes
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260902, 0, 0, NULL);
    
    -- 3. Date with 0 shifts but has notes (e.g. personal appointment)
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260903, 0, 0, 'Devon weekend');
  `);
  db.close();

  try {
    const events = parseShifterFile(tempDbPath);

    // Dates with 0 shifts and no notes should produce no events
    assert.strictEqual(events.filter(e => e.date === '2026-10-01').length, 0);
    assert.strictEqual(events.filter(e => e.date === '2026-10-02').length, 0);

    // Date with notes only should produce a note event
    const noteEvents = events.filter(e => e.date === '2026-10-03');
    assert.strictEqual(noteEvents.length, 1);
    assert.strictEqual(noteEvents[0].title, 'Devon weekend');
    assert.strictEqual(noteEvents[0].isAllDay, true);
    assert.strictEqual(noteEvents[0].source, 'shifter');
  } finally {
    if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);
  }
});

test('5. Read-only safety: Ensuring the parser does not modify the SQLite file', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  assert.ok(fs.existsSync(samplePath), 'Sample database file must exist');

  const statBefore = fs.statSync(samplePath);
  const mtimeBefore = statBefore.mtimeMs;
  const sizeBefore = statBefore.size;

  // Run parser
  const events = parseShifterFile(samplePath);
  assert.ok(events.length > 0);

  const statAfter = fs.statSync(samplePath);
  assert.strictEqual(statAfter.mtimeMs, mtimeBefore, 'File mtime must not change');
  assert.strictEqual(statAfter.size, sizeBefore, 'File size must not change');

  // Verify that DatabaseSync in readOnly mode throws on any write attempt
  const readOnlyDb = new DatabaseSync(samplePath, { readOnly: true });
  assert.throws(() => {
    readOnlyDb.exec("INSERT INTO dias (fecha, turno1, turno2) VALUES (99999999, 1, 0)");
  }, /readonly/i, 'Database connection must reject writes');
  readOnlyDb.close();
});

test('6. Integration with actual sample database: validate known dates and shifts', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  assert.ok(fs.existsSync(samplePath));

  const events = parseShifterFile(samplePath);
  assert.ok(events.length > 1000, 'Should load all historical and scheduled events');

  // 1. Today (2026-10-08, fecha 20260908 in 0-indexed month system): Day Off
  const todayEvents = events.filter(e => e.date === '2026-10-08');
  assert.ok(todayEvents.length >= 1);
  assert.strictEqual(todayEvents[0].title, 'Day Off');
  assert.strictEqual(todayEvents[0].shiftType, 'day_off');
  assert.strictEqual(todayEvents[0].isAllDay, true);
  assert.strictEqual(getDayShiftType(events, '2026-10-08'), 'day_off');

  // 2. 2026-10-03 (fecha 20260903): Nurse LD
  const oct3Shift = events.find(e => e.date === '2026-10-03' && e.shiftType === 'ld');
  assert.ok(oct3Shift);
  assert.strictEqual(oct3Shift.title, 'Nurse LD');
  assert.strictEqual(oct3Shift.startTime, '21:00');
  assert.strictEqual(oct3Shift.endTime, '07:00');
  assert.strictEqual(oct3Shift.isAllDay, false);
  assert.strictEqual(getDayShiftType(events, '2026-10-03'), 'ld');

  // 3. 2026-10-07 (fecha 20260907): Nurse LD + Note "Ohla preceptorship"
  const oct7Events = events.filter(e => e.date === '2026-10-07');
  const oct7Shift = oct7Events.find(e => e.shiftType === 'ld');
  const oct7Note = oct7Events.find(e => e.title.includes('Ohla preceptorship'));
  assert.ok(oct7Shift);
  assert.ok(oct7Note);
  assert.strictEqual(getDayShiftType(events, '2026-10-07'), 'ld');

  // 4. 2026-10-14 (fecha 20260914): Nurse N (Night shift)
  const oct14Night = events.find(e => e.date === '2026-10-14' && e.shiftType === 'night');
  assert.ok(oct14Night);
  assert.strictEqual(oct14Night.title, 'Nurse N');
  assert.strictEqual(getDayShiftType(events, '2026-10-14'), 'night');

  // 5. 2026-10-17 (fecha 20260917): nurse in charge + dorrel + note 'LD' -> classified as 'ld'
  assert.strictEqual(getDayShiftType(events, '2026-10-17'), 'ld');

  // 6. 2026-10-31 (fecha 20260931): Day Off + Halloween note
  const oct31Events = events.filter(e => e.date === '2026-10-31');
  const oct31DayOff = oct31Events.find(e => e.shiftType === 'day_off');
  const oct31Note = oct31Events.find(e => e.title.includes('Halloween'));
  assert.ok(oct31DayOff);
  assert.ok(oct31Note);
  assert.strictEqual(getDayShiftType(events, '2026-10-31'), 'day_off');

  // 7. Canonical accent color helper
  assert.strictEqual(getShiftAccentColor('ld'), 'var(--shift-ld-color, #2D7A4D)');
  assert.strictEqual(getShiftAccentColor('day_off'), 'var(--shift-day-off-color, #C2841B)');
  assert.strictEqual(getShiftAccentColor('night'), 'var(--shift-night-color, #386AA4)');
  assert.strictEqual(getShiftAccentColor('other'), 'var(--shift-other-color, #8C6E50)');
});

test('7. Event pooling: adding new events into an existing pool preserves history without duplicates', () => {
  const existingPool: CalendarEvent[] = [
    {
      id: 'shifter-20260901-t1-1',
      title: 'Day Off',
      memberId: 'sasha',
      date: '2026-10-01',
      isAllDay: true,
      source: 'shifter',
      shiftType: 'day_off'
    },
    {
      id: 'shifter-20260902-t1-3',
      title: 'Nurse LD',
      memberId: 'sasha',
      date: '2026-10-02',
      isAllDay: false,
      startTime: '07:00',
      endTime: '19:30',
      source: 'shifter',
      shiftType: 'ld'
    }
  ];

  // Incoming new events: has one existing event (with updated note) and one brand new event
  const incomingEvents: CalendarEvent[] = [
    {
      id: 'shifter-20260902-t1-3',
      title: 'Nurse LD',
      memberId: 'sasha',
      date: '2026-10-02',
      isAllDay: false,
      startTime: '07:00',
      endTime: '19:30',
      source: 'shifter',
      shiftType: 'ld',
      description: 'Updated shift note'
    },
    {
      id: 'shifter-20260903-t1-6',
      title: 'Nurse N',
      memberId: 'sasha',
      date: '2026-10-03',
      isAllDay: false,
      startTime: '19:00',
      endTime: '07:30',
      source: 'shifter',
      shiftType: 'night'
    }
  ];

  const pooled = poolEvents(existingPool, incomingEvents);
  assert.strictEqual(pooled.length, 3, 'Should have 3 unique events total');

  // Historical event preserved
  assert.ok(pooled.find(e => e.id === 'shifter-20260901-t1-1'));

  // Updated event has new description
  const updated = pooled.find(e => e.id === 'shifter-20260902-t1-3');
  assert.ok(updated);
  assert.strictEqual(updated.description, 'Updated shift note');

  // New event added
  const newEvt = pooled.find(e => e.id === 'shifter-20260903-t1-6');
  assert.ok(newEvt);
  assert.strictEqual(newEvt.shiftType, 'night');

  // Chronologically sorted
  assert.strictEqual(pooled[0].date, '2026-10-01');
  assert.strictEqual(pooled[1].date, '2026-10-02');
  assert.strictEqual(pooled[2].date, '2026-10-03');
});

test('8. Determinism: Parsing the same database twice returns equivalent events', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const run1 = parseShifterFile(samplePath);
  const run2 = parseShifterFile(samplePath);

  assert.strictEqual(run1.length, run2.length, 'Event counts must match exactly');
  assert.deepStrictEqual(run1, run2, 'Event contents and ordering must be identical');
});

test('9. Process-state independence: Calling parser/loader repeatedly does not accumulate events', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const initial = loadShifterEvents(samplePath);
  assert.ok(initial.length > 0, 'Initial load should produce events');

  // Call 5 times consecutively
  for (let i = 0; i < 5; i++) {
    const subsequent = loadShifterEvents(samplePath);
    assert.strictEqual(subsequent.length, initial.length, `Iteration ${i} must not accumulate events`);
    assert.deepStrictEqual(subsequent, initial, `Iteration ${i} must produce identical output`);
  }
});

test('10. Stable IDs: Event IDs remain stable across parses', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const events = parseShifterFile(samplePath);

  // Validate ID format stability
  for (const event of events) {
    assert.ok(
      event.id.startsWith('shifter-'),
      `Event ID '${event.id}' must start with 'shifter-'`
    );
    assert.ok(
      event.id.includes('-t1-') || event.id.includes('-t2-') || event.id.includes('-note-'),
      `Event ID '${event.id}' must indicate shift or note type`
    );
  }

  // Second pass: every single ID must match
  const secondPass = parseShifterFile(samplePath);
  for (let i = 0; i < events.length; i++) {
    assert.strictEqual(events[i].id, secondPass[i].id, `ID at index ${i} must match`);
  }
});

test('11. Duplicate handling: Multiple identical sources do not create duplicate events', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const singleLoad = loadShifterEvents(samplePath);

  // Pass identical file twice in array
  const multiLoad = loadShifterEvents([samplePath, samplePath]);
  assert.strictEqual(multiLoad.length, singleLoad.length, 'Loading same file multiple times must deduplicate');
  assert.deepStrictEqual(multiLoad, singleLoad, 'Multi-load result must match single load exactly');
});

test('12. turno1 and turno2: Both shifts on the same day are handled correctly', () => {
  const tempDbPath = path.resolve('tests/temp_two_shifts.sqlite');
  if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);

  const db = new DatabaseSync(tempDbPath);
  db.exec(`
    CREATE TABLE tablaTurnos (_id INTEGER PRIMARY KEY, texto TEXT, abreviatura TEXT, horaInicio1 TEXT, horaFinal1 TEXT);
    CREATE TABLE dias (fecha INTEGER PRIMARY KEY, turno1 INTEGER, turno2 INTEGER, notas TEXT);
    
    INSERT INTO tablaTurnos (_id, texto, abreviatura, horaInicio1, horaFinal1) VALUES 
      (1, 'Nurse LD', 'LD', '07:00', '19:30'),
      (2, 'Nurse N', 'Night', '19:30', '07:30');
    
    -- Same day with both turno1 and turno2
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260915, 1, 2, 'Double shift day');
  `);
  db.close();

  try {
    const events = parseShifterFile(tempDbPath);
    assert.strictEqual(events.length, 3, 'Should have turno1, turno2, and note event');

    const t1 = events.find(e => e.id.includes('-t1-1'));
    const t2 = events.find(e => e.id.includes('-t2-2'));
    const note = events.find(e => e.id.includes('-note-'));

    assert.ok(t1, 'Turno1 event must be present');
    assert.strictEqual(t1.shiftType, 'ld');
    assert.strictEqual(t1.startTime, '07:00');

    assert.ok(t2, 'Turno2 event must be present');
    assert.strictEqual(t2.shiftType, 'night');
    assert.strictEqual(t2.startTime, '19:30');

    assert.ok(note, 'Note event must be present');
    assert.strictEqual(note.title, 'Double shift day');
  } finally {
    if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);
  }
});

test('13. Error handling: Missing file and non-database file handled gracefully', () => {
  // Non-existent file
  const missingPath = path.resolve('tests/non_existent_calendar.Shifter');
  const missingEvents = loadShifterEvents(missingPath);
  assert.deepStrictEqual(missingEvents, [], 'Missing file must return empty array without throwing');

  // Corrupt / invalid non-sqlite file
  const corruptPath = path.resolve('tests/temp_corrupt.Shifter');
  fs.writeFileSync(corruptPath, 'This is definitely not an SQLite database file!');
  try {
    const corruptEvents = parseShifterFile(corruptPath);
    assert.deepStrictEqual(corruptEvents, [], 'Corrupt file must return empty array without throwing');
  } finally {
    if (fs.existsSync(corruptPath)) fs.unlinkSync(corruptPath);
  }
});

test('14. Restart-equivalent behaviour: Independent calls simulate container restart equivalence', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  
  // First "container session"
  const session1Events = loadShifterEvents(samplePath);
  
  // Second "container session" (since state is stateless/pure, this behaves identically to post-restart)
  const session2Events = loadShifterEvents(samplePath);
  
  assert.strictEqual(session1Events.length, session2Events.length);
  assert.deepStrictEqual(session1Events, session2Events);
});

test('15. sortEvents: sorts chronologically by date, start time, all-day first, and stable ID tie-breaker', () => {
  const unsorted: CalendarEvent[] = [
    { id: 'b', title: 'Later', date: '2026-10-05', startTime: '12:00', memberId: 'sasha', isAllDay: false, source: 'shifter' },
    { id: 'a', title: 'Earlier', date: '2026-10-05', startTime: '08:00', memberId: 'sasha', isAllDay: false, source: 'shifter' },
    { id: 'all-day', title: 'All Day', date: '2026-10-05', memberId: 'sasha', isAllDay: true, source: 'shifter' },
    { id: 'diff-day', title: 'Prev Day', date: '2026-10-04', memberId: 'sasha', isAllDay: true, source: 'shifter' }
  ];
  const sorted = sortEvents(unsorted);
  assert.strictEqual(sorted[0].id, 'diff-day');
  assert.strictEqual(sorted[1].id, 'all-day');
  assert.strictEqual(sorted[2].id, 'a');
  assert.strictEqual(sorted[3].id, 'b');
});

test('16. getShifterFingerprint: produces deterministic fingerprint and responds to changes', () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const fp1 = getShifterFingerprint(samplePath);
  assert.ok(fp1 && fp1 !== 'empty', 'Fingerprint should not be empty for existing file');
  assert.ok(fp1.startsWith('Unnamed.Shifter_'), 'Fingerprint should contain filename');

  const fp2 = getShifterFingerprint(samplePath);
  assert.strictEqual(fp1, fp2, 'Fingerprints must match for unchanged file');

  const missingFp = getShifterFingerprint('/non/existent/path.Shifter');
  assert.strictEqual(missingFp, 'empty', 'Non-existent file should yield "empty"');
});

test('17. In-memory caching: reuses parsed events and invalidates when file changes', () => {
  clearShifterCache();
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');

  const first = parseShifterFile(samplePath);
  const second = parseShifterFile(samplePath);
  assert.strictEqual(first.length, second.length);
  assert.deepStrictEqual(first, second);

  // Modifying mtime updates cache
  const tempDbPath = path.resolve('tests/temp_cache_test.sqlite');
  if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);

  const db = new DatabaseSync(tempDbPath);
  db.exec(`
    CREATE TABLE tablaTurnos (_id INTEGER PRIMARY KEY, texto TEXT, abreviatura TEXT, horaInicio1 TEXT, horaFinal1 TEXT);
    CREATE TABLE dias (fecha INTEGER PRIMARY KEY, turno1 INTEGER, turno2 INTEGER, notas TEXT);
    INSERT INTO tablaTurnos (_id, texto, abreviatura, horaInicio1, horaFinal1) VALUES (1, 'Nurse LD', 'LD', '07:00', '19:30');
    INSERT INTO dias (fecha, turno1, turno2, notas) VALUES (20260901, 1, 0, 'Initial');
  `);
  db.close();

  try {
    const parsed1 = parseShifterFile(tempDbPath);
    assert.strictEqual(parsed1.length, 2);
    const note1 = parsed1.find(e => e.id.includes('-note-'));
    assert.strictEqual(note1?.description, 'Initial');

    // Second parse hits cache
    const parsedCached = parseShifterFile(tempDbPath);
    assert.deepStrictEqual(parsedCached, parsed1);

    // Modify file contents
    const db2 = new DatabaseSync(tempDbPath);
    db2.exec(`UPDATE dias SET notas = 'Updated note' WHERE fecha = 20260901;`);
    db2.close();

    // Ensure mtime is bumped
    const futureTime = new Date(Date.now() + 2000);
    fs.utimesSync(tempDbPath, futureTime, futureTime);

    const parsed2 = parseShifterFile(tempDbPath);
    assert.strictEqual(parsed2.length, 2);
    const note2 = parsed2.find(e => e.id.includes('-note-'));
    assert.strictEqual(note2?.description, 'Updated note');
  } finally {
    if (fs.existsSync(tempDbPath)) fs.unlinkSync(tempDbPath);
  }
});

test('18. /api/calendar endpoint: supports ETag and 304 Not Modified', async () => {
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const prevEnv = process.env.SHIFTER_FILE_PATH;
  process.env.SHIFTER_FILE_PATH = samplePath;

  try {
    // 1. Initial request without If-None-Match
    const req1 = new Request('http://localhost:4321/api/calendar');
    const res1 = await getCalendarApi({ request: req1 } as any);
    assert.strictEqual(res1.status, 200);
    const etag = res1.headers.get('ETag');
    assert.ok(etag, 'Response should contain ETag');
    const body1 = await res1.json();
    assert.ok(Array.isArray(body1) && body1.length > 0);

    // 2. Subsequent request with matching If-None-Match
    const req2 = new Request('http://localhost:4321/api/calendar', {
      headers: { 'If-None-Match': etag! }
    });
    const res2 = await getCalendarApi({ request: req2 } as any);
    assert.strictEqual(res2.status, 304, 'Matching ETag must return 304 Not Modified');
    assert.strictEqual(res2.headers.get('ETag'), etag);

    // 3. Request with mismatched If-None-Match
    const req3 = new Request('http://localhost:4321/api/calendar', {
      headers: { 'If-None-Match': '"outdated-tag"' }
    });
    const res3 = await getCalendarApi({ request: req3 } as any);
    assert.strictEqual(res3.status, 200, 'Mismatched ETag must return 200 OK');
  } finally {
    if (prevEnv !== undefined) {
      process.env.SHIFTER_FILE_PATH = prevEnv;
    } else {
      delete process.env.SHIFTER_FILE_PATH;
    }
  }
});


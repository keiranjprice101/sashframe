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
  clearShifterPool
} from '../src/lib/shifter.ts';

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

test('8. loadShifterEvents cumulative discovery and pool loading', () => {
  clearShifterPool();
  const samplePath = path.resolve('data/shifter/Unnamed.Shifter');
  const events = loadShifterEvents(samplePath);
  assert.ok(events.length > 0);

  // Calling loadShifterEvents again retains events and adds to pool
  const events2 = loadShifterEvents(samplePath);
  assert.strictEqual(events2.length, events.length, 'Deduplication ensures pool size is stable');
});

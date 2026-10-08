import type { CalendarEvent, ShiftType } from './types';

export interface RawShiftDefinition {
  _id: number;
  texto: string;
  abreviatura?: string;
  horaInicio1?: string;
  horaFinal1?: string;
  horaInicio2?: string;
  horaFinal2?: string;
  color?: number;
  colorTexto?: number;
}

export interface RawDiaRow {
  fecha: number;
  turno1: number;
  turno2: number;
  notas?: string | null;
}

export interface ShiftInfo {
  id: number;
  name: string;
  abbreviation: string;
  shiftType: ShiftType;
  startTime?: string;
  endTime?: string;
  isAllDay: boolean;
}

/**
 * Converts Shifter's zero-indexed month integer representation (YYYYMMDD) to ISO YYYY-MM-DD.
 * In Shifter SQLite:
 * Month 00 = January, Month 01 = February, ..., Month 11 = December.
 * For example, 20261008 represents 8 November 2026.
 */
export function parseShifterFecha(fecha: number | string | null | undefined): string | null {
  if (fecha == null) return null;
  const num = typeof fecha === 'number' ? fecha : parseInt(String(fecha).trim(), 10);
  if (isNaN(num)) return null;

  const s = String(num).padStart(8, '0');
  if (s.length !== 8) return null;

  const year = parseInt(s.substring(0, 4), 10);
  const rawMonth = parseInt(s.substring(4, 6), 10); // 0-indexed month (0 = Jan, 11 = Dec)
  const day = parseInt(s.substring(6, 8), 10);

  if (isNaN(year) || isNaN(rawMonth) || isNaN(day)) return null;
  if (rawMonth < 0 || rawMonth > 11) return null;
  if (day < 1 || day > 31) return null;

  // Calendar validation
  const testDate = new Date(year, rawMonth, day);
  if (
    testDate.getFullYear() !== year ||
    testDate.getMonth() !== rawMonth ||
    testDate.getDate() !== day
  ) {
    return null;
  }

  const isoMonth = String(rawMonth + 1).padStart(2, '0');
  const isoDay = String(day).padStart(2, '0');
  return `${year}-${isoMonth}-${isoDay}`;
}

/**
 * Maps shift name, abbreviation and context to canonical shift category:
 * - 'ld' (Long day -> Green)
 * - 'day_off' (Non-working day -> Yellow)
 * - 'night' (Night shift -> Blue)
 * - 'other' (Recognized shift not belonging to the canonical 3 types)
 */
export function classifyShift(
  shiftDef?: RawShiftDefinition | null,
  contextNotes?: string | null
): ShiftType {
  const text = (shiftDef?.texto || '').trim().toLowerCase();
  const abbrev = (shiftDef?.abreviatura || '').trim().toLowerCase();

  // Check Night shift
  if (
    text.includes('nurse n') ||
    text.includes('night') ||
    abbrev.includes('nurse n') ||
    abbrev === 'n' ||
    abbrev === 'night'
  ) {
    return 'night';
  }

  // Check Long Day (LD)
  if (
    text.includes('nurse ld') ||
    text === 'ld' ||
    text.includes('long day') ||
    abbrev.includes('nurse ld') ||
    abbrev === 'ld'
  ) {
    return 'ld';
  }

  // Check Day Off
  if (
    text.includes('day off') ||
    text === 'off' ||
    abbrev.includes('day off') ||
    abbrev === 'off'
  ) {
    return 'day_off';
  }

  // Check contextual LD indicator in notes (e.g. nurse in charge scheduled with LD note)
  if (contextNotes && /\bld\b/i.test(contextNotes)) {
    return 'ld';
  }

  return 'other';
}

/**
 * Determines whether the given time strings represent valid, distinct times.
 */
export function isValidTimeRange(start?: string | null, end?: string | null): boolean {
  if (!start || !end) return false;
  const s = start.trim();
  const e = end.trim();
  if (s === '00:00' && e === '00:00') return false;
  if (s === e) return false;
  return /^\d{1,2}:\d{2}$/.test(s) && /^\d{1,2}:\d{2}$/.test(e);
}

/**
 * Formats a clean human-readable title for a shift.
 */
export function formatShiftTitle(rawText: string, shiftType: ShiftType): string {
  const trimmed = rawText.trim();
  if (!trimmed) {
    switch (shiftType) {
      case 'ld': return 'Nurse LD';
      case 'day_off': return 'Day Off';
      case 'night': return 'Nurse N';
      default: return 'Shift';
    }
  }

  // Standardize common terms nicely
  if (trimmed.toLowerCase() === 'day off') return 'Day Off';
  if (trimmed.toLowerCase() === 'nurse ld') return 'Nurse LD';
  if (trimmed.toLowerCase() === 'nurse n') return 'Nurse N';
  if (trimmed.toLowerCase() === 'study day') return 'Study Day';

  // Capitalize first letter of each word
  return trimmed
    .split(/\s+/)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

/**
 * Helper to determine the primary shift type for a specific calendar date.
 * Used by UI components to tint day cells and display shift badges.
 */
export function getDayShiftType(events: CalendarEvent[], dateIso: string): ShiftType | undefined {
  const dayEvents = events.filter(e => e.date === dateIso && e.source === 'shifter' && e.shiftType);
  if (dayEvents.length === 0) return undefined;

  // Check if a secondary shift was an explicit day off exception
  const dayOffEvent = dayEvents.find(e => e.shiftType === 'day_off');

  // If there's an active night shift
  const nightEvent = dayEvents.find(e => e.shiftType === 'night');
  if (nightEvent) return 'night';

  // If there's an LD shift
  const ldEvent = dayEvents.find(e => e.shiftType === 'ld');
  if (ldEvent) {
    // If there is an explicit swap to day_off on t2, prioritize day off
    if (dayOffEvent && ldEvent.id.includes('-t1-') && dayOffEvent.id.includes('-t2-')) {
      return 'day_off';
    }
    return 'ld';
  }

  // If day off
  if (dayOffEvent) return 'day_off';

  // Any other shift
  return dayEvents[0].shiftType;
}

/**
 * Returns canonical CSS color variable for a shift type.
 */
export function getShiftAccentColor(shiftType?: ShiftType): string {
  switch (shiftType) {
    case 'ld':
      return 'var(--shift-ld-color, #2D7A4D)';
    case 'day_off':
      return 'var(--shift-day-off-color, #C2841B)';
    case 'night':
      return 'var(--shift-night-color, #386AA4)';
    case 'other':
      return 'var(--shift-other-color, #8C6E50)';
    default:
      return 'var(--member-sasha, #2D7A4D)';
  }
}

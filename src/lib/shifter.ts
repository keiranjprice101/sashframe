import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import type { DatabaseSync as DatabaseSyncType } from 'node:sqlite';
import type { CalendarEvent } from './types';
import {
  parseShifterFecha,
  classifyShift,
  isValidTimeRange,
  formatShiftTitle,
  type RawShiftDefinition,
  type RawDiaRow
} from './shifter-utils.ts';

export * from './shifter-utils.ts';

const require = createRequire(import.meta.url);

export function getDatabaseSync(): typeof DatabaseSyncType | null {
  try {
    const sqlite = require('node:sqlite');
    return sqlite.DatabaseSync || null;
  } catch (err) {
    console.warn('[Shifter] Native node:sqlite not available:', err);
    return null;
  }
}

/**
 * In-memory pool of events across reloads.
 * Preserves historical events and accumulates newly discovered ones.
 */
const globalEventPool = new Map<string, CalendarEvent>();

/**
 * Resets the in-memory Shifter event pool (useful for tests).
 */
export function clearShifterPool(): void {
  globalEventPool.clear();
}

/**
 * Discovers all candidate Shifter files from configured paths and standard directories.
 * Files are returned in ascending modification order (oldest to newest).
 */
export function getShifterFiles(): string[] {
  const fileSet = new Set<string>();

  if (process.env.SHIFTER_FILE_PATH) {
    const customPath = path.resolve(process.env.SHIFTER_FILE_PATH);
    if (fs.existsSync(customPath) && !fs.statSync(customPath).isDirectory()) {
      fileSet.add(customPath);
    }
  }

  const searchDirs = [
    process.env.SHIFTER_INPUT_DIR || path.resolve('data/shifter')
  ];

  for (const dir of searchDirs) {
    if (!fs.existsSync(dir)) continue;

    try {
      const entries = fs.readdirSync(dir);
      for (const entry of entries) {
        // Exclude temporary files and directories
        if (entry.toLowerCase().endsWith('.shifter') && !entry.endsWith('.tmp')) {
          const fullPath = path.join(dir, entry);
          if (fs.existsSync(fullPath) && !fs.statSync(fullPath).isDirectory()) {
            fileSet.add(fullPath);
          }
        }
      }
    } catch {
      // Ignore read errors
    }
  }

  // Sort by modification time ascending so newer files overwrite/update older records
  return Array.from(fileSet).sort((a, b) => {
    try {
      return fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs;
    } catch {
      return 0;
    }
  });
}

/**
 * Discovers the primary Shifter file path with fallback priority:
 * 1. SHIFTER_FILE_PATH environment variable (if explicitly configured)
 * 2. Canonical 'calendar.Shifter' if present in discovered files
 * 3. Most recently modified .Shifter file
 */
export function getShifterFilePath(): string | null {
  if (process.env.SHIFTER_FILE_PATH) {
    const customPath = path.resolve(process.env.SHIFTER_FILE_PATH);
    if (fs.existsSync(customPath) && !fs.statSync(customPath).isDirectory()) {
      return customPath;
    }
  }

  const allFiles = getShifterFiles();
  if (allFiles.length === 0) {
    return null;
  }

  // Prefer canonical 'calendar.Shifter' if present
  const canonical = allFiles.find(f => path.basename(f).toLowerCase() === 'calendar.shifter');
  if (canonical) {
    return canonical;
  }

  // Otherwise return the newest file
  return allFiles[allFiles.length - 1];
}

/**
 * Extracts all shift definitions from tablaTurnos.
 */
export function getShiftDefinitions(db: DatabaseSyncType | any): Map<number, RawShiftDefinition> {
  const map = new Map<number, RawShiftDefinition>();
  try {
    const rows = db.prepare('SELECT * FROM tablaTurnos').all() as unknown as RawShiftDefinition[];
    for (const row of rows) {
      map.set(row._id, row);
    }
  } catch {
    // If table doesn't exist or error, return empty map
  }
  return map;
}

/**
 * Safely parses a Shifter SQLite database file and produces normalized CalendarEvents.
 * Opens the database in read-only mode, guaranteeing the source file is never modified.
 */
export function parseShifterFile(filePath: string): CalendarEvent[] {
  if (!fs.existsSync(filePath)) {
    return [];
  }

  const DatabaseSyncClass = getDatabaseSync();
  if (!DatabaseSyncClass) {
    console.warn(`[Shifter] Cannot parse '${filePath}': node:sqlite is unavailable.`);
    return [];
  }

  // Enforce read-only access
  const db = new DatabaseSyncClass(filePath, { readOnly: true });

  try {
    const shiftDefs = getShiftDefinitions(db);

    // Query dias table safely
    const diasQuery = db.prepare(
      'SELECT fecha, turno1, turno2, notas FROM dias ORDER BY fecha ASC'
    );
    const dias = diasQuery.all() as unknown as RawDiaRow[];

    const events: CalendarEvent[] = [];

    for (const dia of dias) {
      const dateIso = parseShifterFecha(dia.fecha);
      if (!dateIso) {
        // Skip invalid dates safely
        continue;
      }

      const notes = (dia.notas || '').trim();
      const hasShift1 = dia.turno1 != null && dia.turno1 > 0;
      const hasShift2 = dia.turno2 != null && dia.turno2 > 0;

      // 1. Process primary shift (turno1)
      if (hasShift1) {
        const def1 = shiftDefs.get(dia.turno1);
        const rawTitle = def1?.texto || (def1?.abreviatura ?? `Shift #${dia.turno1}`);
        const shiftType1 = classifyShift(def1, notes);
        const title1 = formatShiftTitle(rawTitle, shiftType1);

        // Day off is always an all-day event
        const isTimed = shiftType1 !== 'day_off' && isValidTimeRange(def1?.horaInicio1, def1?.horaFinal1);

        events.push({
          id: `shifter-${dia.fecha}-t1-${dia.turno1}`,
          title: title1,
          memberId: 'sasha',
          date: dateIso,
          startTime: isTimed ? def1!.horaInicio1!.trim() : undefined,
          endTime: isTimed ? def1!.horaFinal1!.trim() : undefined,
          isAllDay: !isTimed,
          source: 'shifter',
          shiftType: shiftType1,
          badge: shiftType1 === 'ld' ? 'LD' : shiftType1 === 'day_off' ? 'Off' : shiftType1 === 'night' ? 'Night' : undefined,
          description: notes ? notes : undefined
        });
      }

      // 2. Process secondary shift (turno2) if present
      if (hasShift2) {
        const def2 = shiftDefs.get(dia.turno2);
        const rawTitle2 = def2?.texto || (def2?.abreviatura ?? `Shift #${dia.turno2}`);
        const shiftType2 = classifyShift(def2, null);
        const title2 = formatShiftTitle(rawTitle2, shiftType2);

        const isTimed2 = shiftType2 !== 'day_off' && isValidTimeRange(def2?.horaInicio1, def2?.horaFinal1);

        events.push({
          id: `shifter-${dia.fecha}-t2-${dia.turno2}`,
          title: title2,
          memberId: 'sasha',
          date: dateIso,
          startTime: isTimed2 ? def2!.horaInicio1!.trim() : undefined,
          endTime: isTimed2 ? def2!.horaFinal1!.trim() : undefined,
          isAllDay: !isTimed2,
          source: 'shifter',
          shiftType: shiftType2,
          location: def2?.abreviatura ? def2.abreviatura.trim() : undefined
        });
      }

      // 3. Process notes & exceptions
      if (notes) {
        // Split multi-line notes into separate items
        const lines = notes
          .split(/[\r\n]+/)
          .map(l => l.trim())
          .filter(l => l.length > 0);

        for (let idx = 0; idx < lines.length; idx++) {
          const line = lines[idx];

          // Avoid duplicating simple markers that merely label the shift
          const lower = line.toLowerCase();
          if (lower === 'ld' || lower === 'day off' || lower === 'off' || lower === 'night') {
            continue;
          }

          events.push({
            id: `shifter-${dia.fecha}-note-${idx}`,
            title: line,
            memberId: 'sasha',
            date: dateIso,
            isAllDay: true,
            source: 'shifter',
            description: line
          });
        }
      }
    }

    return events;
  } finally {
    db.close();
  }
}

/**
 * Merges incoming events into an existing pool (or array) without duplicates.
 * Preserves existing events and adds or updates them with incoming ones.
 * Results are sorted chronologically by date and start time.
 */
export function poolEvents(
  existingEvents: CalendarEvent[] | Map<string, CalendarEvent>,
  incomingEvents: CalendarEvent[]
): CalendarEvent[] {
  const pool = existingEvents instanceof Map
    ? new Map(existingEvents)
    : new Map(existingEvents.map(e => [e.id, e]));

  for (const event of incomingEvents) {
    pool.set(event.id, event);
  }

  return Array.from(pool.values()).sort((a, b) => {
    if (a.date !== b.date) return a.date.localeCompare(b.date);
    if (a.startTime && b.startTime) return a.startTime.localeCompare(b.startTime);
    if (a.isAllDay && !b.isAllDay) return -1;
    if (!a.isAllDay && b.isAllDay) return 1;
    return a.id.localeCompare(b.id);
  });
}

/**
 * Loads Shifter events with automatic discovery and pool accumulation.
 * Scans available Shifter files, parses their events, and merges any newly
 * added events into the existing pool without data loss or duplicates.
 *
 * @param explicitPath Optional specific file to load instead of auto-discovery.
 * @param options.reset If true, clears the in-memory pool before loading.
 */
export function loadShifterEvents(
  explicitPath?: string,
  options?: { reset?: boolean }
): CalendarEvent[] {
  if (options?.reset) {
    globalEventPool.clear();
  }

  const filesToLoad: string[] = [];
  if (explicitPath) {
    if (fs.existsSync(explicitPath)) {
      filesToLoad.push(explicitPath);
    }
  } else {
    filesToLoad.push(...getShifterFiles());
  }

  if (filesToLoad.length === 0) {
    return Array.from(globalEventPool.values());
  }

  for (const filePath of filesToLoad) {
    try {
      const fileEvents = parseShifterFile(filePath);
      for (const event of fileEvents) {
        globalEventPool.set(event.id, event);
      }
    } catch (err) {
      console.warn(`[Shifter] Failed to parse file at ${filePath}:`, err);
    }
  }

  return Array.from(globalEventPool.values()).sort((a, b) => {
    if (a.date !== b.date) return a.date.localeCompare(b.date);
    if (a.startTime && b.startTime) return a.startTime.localeCompare(b.startTime);
    if (a.isAllDay && !b.isAllDay) return -1;
    if (!a.isAllDay && b.isAllDay) return 1;
    return a.id.localeCompare(b.id);
  });
}

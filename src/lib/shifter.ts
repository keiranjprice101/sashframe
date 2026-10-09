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
 * Deterministically sorts calendar events chronologically by date and start time,
 * with all-day events ordered first, and event ID as a tie-breaker.
 */
export function sortEvents(events: CalendarEvent[]): CalendarEvent[] {
  return events.slice().sort((a, b) => {
    if (a.date !== b.date) return a.date.localeCompare(b.date);
    if (a.startTime && b.startTime) return a.startTime.localeCompare(b.startTime);
    if (a.isAllDay && !b.isAllDay) return -1;
    if (!a.isAllDay && b.isAllDay) return 1;
    return a.id.localeCompare(b.id);
  });
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

interface ShifterCacheEntry {
  mtimeMs: number;
  size: number;
  ino: number;
  events: CalendarEvent[];
}

const fileCache = new Map<string, ShifterCacheEntry>();

/**
 * Clears the in-memory parsed Shifter database cache.
 */
export function clearShifterCache(): void {
  fileCache.clear();
}

/**
 * Computes a lightweight fingerprint/ETag string representing the current state of Shifter files.
 * Uses file modification timestamp, size, and basename without reading or parsing database contents.
 */
export function getShifterFingerprint(explicitPath?: string | string[]): string {
  const filesToLoad: string[] = [];

  if (explicitPath) {
    const paths = Array.isArray(explicitPath) ? explicitPath : [explicitPath];
    for (const p of paths) {
      if (fs.existsSync(p)) {
        filesToLoad.push(p);
      }
    }
  } else {
    const primary = getShifterFilePath();
    if (primary && fs.existsSync(primary)) {
      filesToLoad.push(primary);
    }
  }

  if (filesToLoad.length === 0) {
    return 'empty';
  }

  const parts = filesToLoad.map(f => {
    try {
      const st = fs.statSync(f);
      return `${path.basename(f)}_${st.mtimeMs.toString(36)}_${st.size.toString(36)}`;
    } catch {
      return `${path.basename(f)}_0_0`;
    }
  });

  return parts.join(';');
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
 * Utilizes an in-memory cache keyed by path, mtime, size, and inode to eliminate redundant SQLite parsing.
 */
export function parseShifterFile(filePath: string): CalendarEvent[] {
  if (!fs.existsSync(filePath)) {
    console.warn(`[Shifter] File does not exist: ${filePath}`);
    return [];
  }

  let stat: fs.Stats | null = null;
  try {
    stat = fs.statSync(filePath);
    const cached = fileCache.get(filePath);
    if (
      cached &&
      cached.mtimeMs === stat.mtimeMs &&
      cached.size === stat.size &&
      cached.ino === stat.ino
    ) {
      return cached.events.slice();
    }
  } catch {
    // If stat fails, proceed to attempt open
  }

  const DatabaseSyncClass = getDatabaseSync();
  if (!DatabaseSyncClass) {
    console.warn(`[Shifter] Cannot parse '${filePath}': node:sqlite is unavailable.`);
    return [];
  }

  let db: DatabaseSyncType | null = null;
  try {
    // Enforce read-only access
    db = new DatabaseSyncClass(filePath, { readOnly: true });

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

    const sorted = sortEvents(events);
    if (stat) {
      fileCache.set(filePath, {
        mtimeMs: stat.mtimeMs,
        size: stat.size,
        ino: stat.ino,
        events: sorted
      });
    }
    return sorted.slice();
  } catch (err) {
    console.warn(`[Shifter] Failed to parse Shifter SQLite file '${filePath}':`, err);
    return [];
  } finally {
    if (db) {
      try {
        db.close();
      } catch {
        // Ignore close error
      }
    }
  }
}

/**
 * Merges incoming events into an existing pool (or array) without duplicates.
 * Pure function: merges by stable event ID and sorts deterministically.
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

  return sortEvents(Array.from(pool.values()));
}

/**
 * Loads Shifter events deterministically from persistent storage.
 * Reads the canonical Shifter database file (or explicit path), parses events in read-only mode,
 * and returns the normalized, sorted event list.
 *
 * Fully deterministic: identical persistent input produces identical output.
 * No mutable module-level or in-memory state is retained across requests or process lifetime.
 *
 * @param explicitPath Optional specific file path or array of paths to load instead of auto-discovery.
 */
export function loadShifterEvents(explicitPath?: string | string[]): CalendarEvent[] {
  const filesToLoad: string[] = [];

  if (explicitPath) {
    const paths = Array.isArray(explicitPath) ? explicitPath : [explicitPath];
    for (const p of paths) {
      if (fs.existsSync(p)) {
        filesToLoad.push(p);
      } else {
        console.warn(`[Shifter] Specified path does not exist: ${p}`);
      }
    }
  } else {
    const primary = getShifterFilePath();
    if (primary && fs.existsSync(primary)) {
      filesToLoad.push(primary);
    }
  }

  if (filesToLoad.length === 0) {
    return [];
  }

  // Deduplicate across files locally per request (no global/module-level mutable state)
  const eventMap = new Map<string, CalendarEvent>();

  for (const filePath of filesToLoad) {
    try {
      const fileEvents = parseShifterFile(filePath);
      for (const event of fileEvents) {
        eventMap.set(event.id, event);
      }
    } catch (err) {
      console.warn(`[Shifter] Failed to parse file at ${filePath}:`, err);
    }
  }

  return sortEvents(Array.from(eventMap.values()));
}

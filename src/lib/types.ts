export type ShiftType = 'ld' | 'day_off' | 'night' | 'other';

export interface CalendarEvent {
  id: string;
  title: string;
  date: string; // YYYY-MM-DD
  startTime?: string; // HH:mm format (e.g., "09:30")
  endTime?: string; // HH:mm format (e.g., "11:00")
  isAllDay: boolean;
  location?: string;
  description?: string;
  source?: 'shifter' | 'mock' | 'manual' | string;
  shiftType?: ShiftType;
  badge?: string;
}

export interface Weather {
  temperature: number;
  unit: string;
  condition: string;
  high?: number;
  low?: number;
}

export interface PhotoManifestItem {
  id: string;
  src: string;
  sourceName: string;
  width: number;
  height: number;
  updatedAt: string;
}

export interface Photo {
  id: string;
  url: string;
  caption?: string;
  location?: string;
  sourceName?: string;
  width?: number;
  height?: number;
}

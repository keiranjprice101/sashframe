export interface HouseholdMember {
  id: string;
  name: string;
  color: string; // Primary hex color (e.g., #E26D5C)
  bgColor: string; // Soft background color for cards (e.g., #FDF2F0)
  borderColor: string;
  textColor: string;
  initials: string;
}

export interface CalendarEvent {
  id: string;
  title: string;
  memberId: string;
  date: string; // YYYY-MM-DD
  startTime?: string; // HH:mm format (e.g., "09:30")
  endTime?: string; // HH:mm format (e.g., "11:00")
  isAllDay: boolean;
  location?: string;
  description?: string;
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

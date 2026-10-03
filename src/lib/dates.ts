/**
 * Helper utilities for date calculations and formatting.
 */

export function getStartOfWeek(d: Date = new Date()): Date {
  const date = new Date(d);
  const day = date.getDay(); // 0 is Sunday, 1 is Monday, ...
  const diff = date.getDate() - day + (day === 0 ? -6 : 1); // Adjust when Sunday to make Monday start of week
  const start = new Date(date.setDate(diff));
  start.setHours(0, 0, 0, 0);
  return start;
}

export function getWeekDays(startOfWeek: Date): Date[] {
  const days: Date[] = [];
  for (let i = 0; i < 7; i++) {
    const day = new Date(startOfWeek);
    day.setDate(startOfWeek.getDate() + i);
    days.push(day);
  }
  return days;
}

export function formatDateIso(date: Date): string {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

export function formatDisplayDate(date: Date, timeZone: string = 'Europe/London'): string {
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone
  }).format(date);
}

export function formatDayName(date: Date, timeZone: string = 'Europe/London'): string {
  return new Intl.DateTimeFormat('en-GB', { 
    weekday: 'long',
    timeZone
  }).format(date);
}

export function formatDayShort(date: Date, timeZone: string = 'Europe/London'): string {
  return new Intl.DateTimeFormat('en-GB', { 
    weekday: 'short',
    timeZone
  }).format(date);
}

export function formatLiveTime(date: Date, timeZone: string = 'Europe/London'): string {
  return new Intl.DateTimeFormat('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone
  }).format(date);
}

export function formatTime12h(timeStr?: string): string {
  if (!timeStr) return '';
  const [hoursStr, minutesStr] = timeStr.split(':');
  const hours = parseInt(hoursStr, 10);
  if (isNaN(hours)) return timeStr;
  const period = hours >= 12 ? 'PM' : 'AM';
  const h12 = hours % 12 || 12;
  return `${h12}:${minutesStr} ${period}`;
}

export function isSameDay(date1: Date, date2: Date): boolean {
  return (
    date1.getFullYear() === date2.getFullYear() &&
    date1.getMonth() === date2.getMonth() &&
    date1.getDate() === date2.getDate()
  );
}

export function isToday(date: Date): boolean {
  return isSameDay(date, new Date());
}

export function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

export function addWeeks(date: Date, weeks: number): Date {
  return addDays(date, weeks * 7);
}

export function formatWeekRange(start: Date, end: Date): string {
  const sameYear = start.getFullYear() === end.getFullYear();
  const sameMonth = sameYear && start.getMonth() === end.getMonth();

  const startMonth = start.toLocaleDateString('en-US', { month: 'long' });
  const endMonth = end.toLocaleDateString('en-US', { month: 'long' });

  if (sameMonth) {
    return `${startMonth} ${start.getDate()} – ${end.getDate()}`;
  } else if (sameYear) {
    return `${startMonth} ${start.getDate()} – ${endMonth} ${end.getDate()}`;
  } else {
    return `${startMonth} ${start.getDate()}, ${start.getFullYear()} – ${endMonth} ${end.getDate()}, ${end.getFullYear()}`;
  }
}

export interface MonthGridDay {
  date: Date;
  dateIso: string;
  dayNumber: number;
  isCurrentMonth: boolean;
  isToday: boolean;
  isWeekend: boolean;
}

export interface MonthGridData {
  monthName: string;
  year: number;
  title: string;
  totalWeeks: number;
  days: MonthGridDay[];
}

export function getMonthGrid(referenceDate: Date = new Date()): MonthGridData {
  const year = referenceDate.getFullYear();
  const month = referenceDate.getMonth(); // 0-11

  const firstDayOfMonth = new Date(year, month, 1);
  const lastDayOfMonth = new Date(year, month + 1, 0);
  const daysInMonth = lastDayOfMonth.getDate();

  // Monday-based week: Monday is 0, Sunday is 6
  const startDayOfWeek = (firstDayOfMonth.getDay() + 6) % 7;

  // Preceding days from previous month to align with Monday
  const totalDays = startDayOfWeek + daysInMonth;
  const totalWeeks = Math.ceil(totalDays / 7);
  const totalGridDays = totalWeeks * 7;

  const days: MonthGridDay[] = [];
  const today = new Date();

  for (let i = 0; i < totalGridDays; i++) {
    const dayOffset = i - startDayOfWeek;
    const date = new Date(year, month, 1 + dayOffset);
    date.setHours(0, 0, 0, 0);

    const isCurrentMonth = date.getMonth() === month;
    const isTodayDate = isSameDay(date, today);
    const dayOfWeek = (date.getDay() + 6) % 7;
    const isWeekend = dayOfWeek >= 5;

    days.push({
      date,
      dateIso: formatDateIso(date),
      dayNumber: date.getDate(),
      isCurrentMonth,
      isToday: isTodayDate,
      isWeekend
    });
  }

  const monthName = new Intl.DateTimeFormat('en-GB', { month: 'long', timeZone: 'Europe/London' }).format(firstDayOfMonth);
  const title = `${monthName} ${year}`;

  return {
    monthName,
    year,
    title,
    totalWeeks,
    days
  };
}

<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { getMonthGrid } from '../lib/dates';
  import { HOUSEHOLD_MEMBERS } from '../data/mock';
  import { getDayShiftType, getShiftAccentColor } from '../lib/shifter-utils';

  interface Props {
    events: CalendarEvent[];
    members?: Record<string, HouseholdMember>;
  }

  let { 
    events, 
    members = HOUSEHOLD_MEMBERS 
  }: Props = $props();

  let now = $state(new Date());
  let timer: ReturnType<typeof setInterval>;

  onMount(() => {
    // Keep date updated live (checks every 30 seconds for day/month rollover)
    timer = setInterval(() => {
      now = new Date();
    }, 30000);
  });

  onDestroy(() => {
    if (timer) clearInterval(timer);
  });

  let monthData = $derived(getMonthGrid(now));

  // Max events visible per cell based on 5 vs 6 week months
  let maxVisibleEvents = $derived(monthData.totalWeeks === 5 ? 4 : 3);

  const WEEKDAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  function getEventsForDay(iso: string): CalendarEvent[] {
    return events
      .filter(e => e.date === iso)
      .sort((a, b) => {
        if (a.isAllDay && !b.isAllDay) return -1;
        if (!a.isAllDay && b.isAllDay) return 1;
        return (a.startTime || '').localeCompare(b.startTime || '');
      });
  }
</script>

<div class="calendar-month">
  <!-- Month Masthead: Refined typographic heading, zero buttons/controls -->
  <header class="month-masthead">
    <h1 class="month-title">{monthData.title}</h1>
  </header>

  <!-- Weekday Columns Header (Mon - Sun) -->
  <div class="weekday-row">
    {#each WEEKDAY_NAMES as dayName}
      <div class="weekday-cell">
        <span class="weekday-label">{dayName}</span>
      </div>
    {/each}
  </div>

  <!-- Full Month Grid -->
  <div 
    class="month-grid" 
    style="--total-weeks: {monthData.totalWeeks};"
  >
    {#each monthData.days as day (day.dateIso)}
      {@const dayEvents = getEventsForDay(day.dateIso)}
      {@const dayShift = getDayShiftType(events, day.dateIso)}
      {@const visibleEvents = dayEvents.slice(0, maxVisibleEvents)}
      {@const extraCount = dayEvents.length - maxVisibleEvents}

      <div 
        class="day-cell" 
        class:is-today={day.isToday}
        class:other-month={!day.isCurrentMonth}
        class:shift-day-ld={dayShift === 'ld'}
        class:shift-day-off={dayShift === 'day_off'}
        class:shift-day-night={dayShift === 'night'}
        class:shift-day-other={dayShift === 'other'}
      >
        <!-- Day Cell Header: Number / Today Pill / Shift Badge -->
        <div class="day-cell-top">
          <div class="day-number" class:active-today={day.isToday}>
            {#if day.dayNumber === 1 && !day.isToday}
              <span class="first-month-tag">
                {day.date.toLocaleDateString('en-GB', { month: 'short' })}
              </span>
            {/if}
            <span class="num-text">{day.dayNumber}</span>
          </div>

          {#if dayShift}
            <span class="month-shift-badge shift-badge-{dayShift}">
              {#if dayShift === 'ld'}LD{:else if dayShift === 'day_off'}Off{:else if dayShift === 'night'}Night{:else}Shift{/if}
            </span>
          {/if}
        </div>

        <!-- Day Events List -->
        <div class="day-events">
          {#each visibleEvents as event (event.id)}
            {@const member = members[event.memberId] || members.alex}
            {@const accentColor = event.shiftType ? getShiftAccentColor(event.shiftType) : (event.color || `var(--member-${event.memberId}, ${member.color})`)}
            <div 
              class="month-event"
              class:is-all-day={event.isAllDay}
              class:is-shift={!!event.shiftType}
            >
              <span 
                class="event-accent" 
                style="background-color: {accentColor}"
              ></span>
              <div class="event-info">
                {#if !event.isAllDay && event.startTime}
                  <span class="event-time">{event.startTime}</span>
                {/if}
                <span class="event-title">{event.title}</span>
              </div>
            </div>
          {/each}

          {#if extraCount > 0}
            <div class="more-indicator">
              +{extraCount} more
            </div>
          {/if}
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .calendar-month {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100%;
    background-color: var(--bg-surface);
    overflow: hidden;
  }

  /* Masthead */
  .month-masthead {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    padding: 1.4rem 2rem 1.15rem 2rem;
    border-bottom: 1px solid var(--border-hairline);
    flex-shrink: 0;
  }

  .month-title {
    font-size: 2.1rem;
    font-weight: 500;
    color: var(--text-main);
    letter-spacing: -0.025em;
    line-height: 1.1;
  }

  /* Weekday Header Row */
  .weekday-row {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    border-bottom: 1px solid var(--border-hairline);
    flex-shrink: 0;
    background-color: var(--bg-surface);
  }

  .weekday-cell {
    padding: 0.75rem 0.85rem;
    border-right: 1px solid var(--border-hairline);
  }

  .weekday-cell:last-child {
    border-right: none;
  }

  .weekday-label {
    font-size: 0.76rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--text-muted);
  }

  /* Month Grid */
  .month-grid {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    grid-template-rows: repeat(var(--total-weeks, 5), 1fr);
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }

  /* Day Cell */
  .day-cell {
    display: flex;
    flex-direction: column;
    padding: 0.55rem 0.65rem 0.45rem 0.65rem;
    background-color: var(--bg-surface);
    border-right: 1px solid var(--border-hairline);
    border-bottom: 1px solid var(--border-hairline);
    overflow: hidden;
    min-height: 0;
  }

  /* Remove right border on the 7th column of each row */
  .day-cell:nth-child(7n) {
    border-right: none;
  }

  /* Other month days are softened */
  .day-cell.other-month {
    background-color: rgba(0, 0, 0, 0.015);
  }

  :global(html[data-theme="dark"]) .day-cell.other-month {
    background-color: rgba(255, 255, 255, 0.015);
  }

  .day-cell.other-month .num-text {
    opacity: 0.35;
    color: var(--text-light);
  }

  .day-cell.other-month .day-events {
    opacity: 0.45;
  }

  /* Today subtle highlight */
  .day-cell.is-today {
    background-color: var(--bg-surface-elevated);
  }

  /* Shifter Shift Day Backgrounds */
  .day-cell.shift-day-ld {
    background-color: var(--shift-ld-bg);
  }
  .day-cell.shift-day-off {
    background-color: var(--shift-day-off-bg);
  }
  .day-cell.shift-day-night {
    background-color: var(--shift-night-bg);
  }
  .day-cell.shift-day-other {
    background-color: var(--shift-other-bg);
  }

  /* Other month days with shifts remain muted */
  .day-cell.other-month.shift-day-ld {
    background-color: rgba(45, 122, 77, 0.035);
  }
  .day-cell.other-month.shift-day-off {
    background-color: rgba(212, 148, 26, 0.035);
  }
  .day-cell.other-month.shift-day-night {
    background-color: rgba(56, 106, 164, 0.035);
  }
  .day-cell.other-month.shift-day-other {
    background-color: rgba(140, 110, 80, 0.03);
  }

  :global(html[data-theme="dark"]) .day-cell.other-month.shift-day-ld {
    background-color: rgba(78, 173, 119, 0.045);
  }
  :global(html[data-theme="dark"]) .day-cell.other-month.shift-day-off {
    background-color: rgba(217, 164, 67, 0.045);
  }
  :global(html[data-theme="dark"]) .day-cell.other-month.shift-day-night {
    background-color: rgba(85, 143, 207, 0.05);
  }
  :global(html[data-theme="dark"]) .day-cell.other-month.shift-day-other {
    background-color: rgba(172, 147, 122, 0.04);
  }

  /* Day Number Top Row */
  .day-cell-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    flex-shrink: 0;
    line-height: 1;
  }

  /* Month shift badge in day header */
  .month-shift-badge {
    font-size: 0.65rem;
    font-weight: 650;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 0.12rem 0.4rem;
    border-radius: var(--radius-sm);
    line-height: 1.1;
    margin-left: auto;
  }

  .month-shift-badge.shift-badge-ld {
    color: var(--shift-ld-text);
    background-color: rgba(45, 122, 77, 0.14);
    border: 1px solid var(--shift-ld-border);
  }

  .month-shift-badge.shift-badge-day_off {
    color: var(--shift-day-off-text);
    background-color: rgba(212, 148, 26, 0.14);
    border: 1px solid var(--shift-day-off-border);
  }

  .month-shift-badge.shift-badge-night {
    color: var(--shift-night-text);
    background-color: rgba(56, 106, 164, 0.14);
    border: 1px solid var(--shift-night-border);
  }

  .month-shift-badge.shift-badge-other {
    color: var(--shift-other-text);
    background-color: rgba(140, 110, 80, 0.12);
    border: 1px solid var(--shift-other-border);
  }

  :global(html[data-theme="dark"]) .month-shift-badge.shift-badge-ld {
    background-color: rgba(78, 173, 119, 0.20);
  }
  :global(html[data-theme="dark"]) .month-shift-badge.shift-badge-day_off {
    background-color: rgba(217, 164, 67, 0.20);
  }
  :global(html[data-theme="dark"]) .month-shift-badge.shift-badge-night {
    background-color: rgba(85, 143, 207, 0.22);
  }
  :global(html[data-theme="dark"]) .month-shift-badge.shift-badge-other {
    background-color: rgba(172, 147, 122, 0.18);
  }

  .day-number {
    display: inline-flex;
    align-items: baseline;
    gap: 0.25rem;
    font-size: 1.15rem;
    font-weight: 400;
    color: var(--text-main);
    font-variant-numeric: tabular-nums;
  }

  .first-month-tag {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-muted);
  }

  .day-number.active-today {
    background-color: var(--accent-walnut);
    color: var(--accent-walnut-text);
    font-weight: 500;
    width: 1.85rem;
    height: 1.85rem;
    border-radius: var(--radius-full);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 1.05rem;
    padding: 0;
  }

  /* Events inside Day Cell */
  .day-events {
    display: flex;
    flex-direction: column;
    gap: 0.28rem;
    margin-top: 0.35rem;
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }

  .month-event {
    display: flex;
    align-items: baseline;
    gap: 0.38rem;
    line-height: 1.25;
    min-width: 0;
  }

  .event-accent {
    width: 2.5px;
    height: 1.05em;
    border-radius: 1px;
    flex-shrink: 0;
    align-self: flex-start;
    margin-top: 0.15em;
    opacity: 0.9;
  }

  .event-info {
    display: flex;
    align-items: baseline;
    gap: 0.3rem;
    min-width: 0;
    flex: 1;
    overflow: hidden;
  }

  .event-time {
    font-size: 0.72rem;
    font-weight: 600;
    color: var(--text-muted);
    font-variant-numeric: tabular-nums;
    flex-shrink: 0;
  }

  .event-title {
    font-size: 0.79rem;
    font-weight: 500;
    color: var(--text-main);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .month-event.is-all-day .event-title {
    font-weight: 600;
  }

  .more-indicator {
    font-size: 0.68rem;
    font-weight: 550;
    color: var(--text-muted);
    padding-left: calc(2.5px + 0.38rem);
    line-height: 1.2;
    margin-top: 0.05rem;
  }

  /* Responsive tuning for smaller displays (e.g. 1366x768) */
  @media (max-width: 1366px) {
    .month-masthead {
      padding: 1rem 1.5rem 0.85rem 1.5rem;
    }
    .month-title {
      font-size: 1.7rem;
    }
    .weekday-cell {
      padding: 0.55rem 0.65rem;
    }
    .weekday-label {
      font-size: 0.7rem;
    }
    .day-cell {
      padding: 0.4rem 0.5rem 0.35rem 0.5rem;
    }
    .day-number {
      font-size: 1rem;
    }
    .day-number.active-today {
      width: 1.6rem;
      height: 1.6rem;
      font-size: 0.92rem;
    }
    .event-time {
      font-size: 0.66rem;
    }
    .event-title {
      font-size: 0.72rem;
    }
    .more-indicator {
      font-size: 0.64rem;
    }
  }
</style>

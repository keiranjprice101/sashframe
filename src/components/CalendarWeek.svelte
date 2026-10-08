<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { getStartOfWeek, getWeekDays, formatDateIso, isToday, addDays, formatWeekRange } from '../lib/dates';
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
    // Keep date updated live every 30 seconds
    timer = setInterval(() => {
      now = new Date();
    }, 30000);
  });

  onDestroy(() => {
    if (timer) clearInterval(timer);
  });

  let currentWeekStart = $derived(getStartOfWeek(now));
  let weekEnd = $derived(addDays(currentWeekStart, 6));
  let formattedRange = $derived(formatWeekRange(currentWeekStart, weekEnd));
  let weekDays = $derived(getWeekDays(currentWeekStart));

  // Map events per day ISO string
  function getEventsForDay(date: Date): { allDay: CalendarEvent[]; timed: CalendarEvent[] } {
    const iso = formatDateIso(date);
    const dayEvents = events.filter(e => e.date === iso);
    
    const allDay = dayEvents.filter(e => e.isAllDay);
    const timed = dayEvents
      .filter(e => !e.isAllDay)
      .sort((a, b) => (a.startTime || '').localeCompare(b.startTime || ''));

    return { allDay, timed };
  }
</script>

<div class="calendar-week-container">
  <!-- Week Masthead: Consistent with month masthead, zero buttons/controls -->
  <header class="week-masthead">
    <h1 class="week-title">{formattedRange}</h1>
  </header>

  <!-- 7-Day Columns Grid -->
  <div class="calendar-grid">
    {#each weekDays as day (day.toISOString())}
      {@const iso = formatDateIso(day)}
      {@const { allDay, timed } = getEventsForDay(day)}
      {@const todayClass = isToday(day)}
      {@const dayShift = getDayShiftType(events, iso)}

      <div 
        class="day-column" 
        class:is-today={todayClass}
        class:shift-col-ld={dayShift === 'ld'}
        class:shift-col-off={dayShift === 'day_off'}
        class:shift-col-night={dayShift === 'night'}
        class:shift-col-other={dayShift === 'other'}
      >
        <!-- Day Header: Unboxed, typographic, editorial -->
        <div class="day-header">
          <div class="day-header-top">
            <span class="day-name">{day.toLocaleDateString('en-GB', { weekday: 'short' })}</span>
            {#if dayShift}
              <span class="week-shift-pill shift-badge-{dayShift}">
                {#if dayShift === 'ld'}LD{:else if dayShift === 'day_off'}Off{:else if dayShift === 'night'}Night{:else}Shift{/if}
              </span>
            {/if}
          </div>
          <div class="day-number" class:active-today={todayClass}>
            {day.getDate()}
          </div>
        </div>

        <!-- Day Body: Generous breathing room, schedule typography -->
        <div class="day-body">
          <!-- All-Day Events Section -->
          {#if allDay.length > 0}
            <div class="all-day-section">
              {#each allDay as event (event.id)}
                {@const member = members[event.memberId] || members.alex}
                {@const accentColor = event.shiftType ? getShiftAccentColor(event.shiftType) : (event.color || `var(--member-${event.memberId}, ${member.color})`)}
                <div class="schedule-entry all-day-entry">
                  <span class="entry-time-label">All day</span>
                  <div class="entry-title-row">
                    <span class="accent-bar" style="background-color: {accentColor}"></span>
                    <span class="entry-title">{event.title}</span>
                  </div>
                  {#if event.location}
                    <span class="entry-meta">{event.location}</span>
                  {/if}
                </div>
              {/each}
            </div>
          {/if}

          <!-- Timed Events Section -->
          <div class="timed-events-list">
            {#each timed as event (event.id)}
              {@const member = members[event.memberId] || members.alex}
              {@const accentColor = event.shiftType ? getShiftAccentColor(event.shiftType) : (event.color || `var(--member-${event.memberId}, ${member.color})`)}
              <div class="schedule-entry timed-entry">
                <div class="entry-time-label">
                  {event.startTime}
                  {#if event.endTime}
                    <span class="time-end">– {event.endTime}</span>
                  {/if}
                </div>
                <div class="entry-title-row">
                  <span class="accent-bar" style="background-color: {accentColor}"></span>
                  <span class="entry-title">{event.title}</span>
                </div>
                {#if event.location}
                  <span class="entry-meta">{event.location}</span>
                {/if}
              </div>
            {/each}
          </div>
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .calendar-week-container {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100%;
    background-color: var(--bg-surface);
    overflow: hidden;
  }

  /* Week Masthead */
  .week-masthead {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    padding: 1.4rem 2rem 1.15rem 2rem;
    border-bottom: 1px solid var(--border-hairline);
    flex-shrink: 0;
  }

  .week-title {
    font-size: 2.1rem;
    font-weight: 500;
    color: var(--text-main);
    letter-spacing: -0.025em;
    line-height: 1.1;
  }

  /* 7-Day Grid */
  .calendar-grid {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    flex: 1;
    min-height: 0;
    width: 100%;
    background-color: transparent;
    overflow: hidden;
  }

  .day-column {
    display: flex;
    flex-direction: column;
    background-color: var(--bg-surface);
    height: 100%;
    overflow: hidden;
    padding: 0 0.85rem;
    border-right: 1px solid var(--border-hairline);
  }

  .day-column:last-child {
    border-right: none;
  }

  .day-column.is-today {
    background-color: var(--bg-surface-elevated);
  }

  /* Shifter Shift Day Column Tinting */
  .day-column.shift-col-ld {
    background-color: var(--shift-ld-bg);
  }
  .day-column.shift-col-off {
    background-color: var(--shift-day-off-bg);
  }
  .day-column.shift-col-night {
    background-color: var(--shift-night-bg);
  }
  .day-column.shift-col-other {
    background-color: var(--shift-other-bg);
  }

  /* Day Header */
  .day-header {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    padding: 1.15rem 0.25rem 0.85rem 0.25rem;
    background: transparent;
    border-bottom: 1px solid var(--border-hairline);
    gap: 0.35rem;
    flex-shrink: 0;
  }

  .day-header-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
  }

  /* Week shift pill in day header */
  .week-shift-pill {
    font-size: 0.65rem;
    font-weight: 650;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 0.12rem 0.4rem;
    border-radius: var(--radius-sm);
    line-height: 1.1;
  }

  .week-shift-pill.shift-badge-ld {
    color: var(--shift-ld-text);
    background-color: rgba(45, 122, 77, 0.14);
    border: 1px solid var(--shift-ld-border);
  }

  .week-shift-pill.shift-badge-day_off {
    color: var(--shift-day-off-text);
    background-color: rgba(212, 148, 26, 0.14);
    border: 1px solid var(--shift-day-off-border);
  }

  .week-shift-pill.shift-badge-night {
    color: var(--shift-night-text);
    background-color: rgba(56, 106, 164, 0.14);
    border: 1px solid var(--shift-night-border);
  }

  .week-shift-pill.shift-badge-other {
    color: var(--shift-other-text);
    background-color: rgba(140, 110, 80, 0.12);
    border: 1px solid var(--shift-other-border);
  }

  :global(html[data-theme="dark"]) .week-shift-pill.shift-badge-ld {
    background-color: rgba(78, 173, 119, 0.20);
  }
  :global(html[data-theme="dark"]) .week-shift-pill.shift-badge-day_off {
    background-color: rgba(217, 164, 67, 0.20);
  }
  :global(html[data-theme="dark"]) .week-shift-pill.shift-badge-night {
    background-color: rgba(85, 143, 207, 0.22);
  }
  :global(html[data-theme="dark"]) .week-shift-pill.shift-badge-other {
    background-color: rgba(172, 147, 122, 0.18);
  }

  .day-name {
    font-size: 0.76rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--text-muted);
  }

  .day-number {
    width: 2.25rem;
    height: 2.25rem;
    border-radius: var(--radius-full);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.65rem;
    font-weight: 400;
    color: var(--text-main);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .day-number.active-today {
    background-color: var(--accent-walnut);
    color: var(--accent-walnut-text);
    font-size: 1.15rem;
    font-weight: 500;
    width: 2rem;
    height: 2rem;
  }

  /* Day Body & Events */
  .day-body {
    flex: 1;
    display: flex;
    flex-direction: column;
    padding: 1.15rem 0.25rem 1.25rem 0.25rem;
    overflow-y: auto;
  }

  .all-day-section {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    padding-bottom: 0.85rem;
    margin-bottom: 0.85rem;
    border-bottom: 1px solid var(--border-hairline);
  }

  .timed-events-list {
    display: flex;
    flex-direction: column;
    gap: 1.15rem;
  }

  /* Schedule Entry: Typeset schedule, non-touch presentation */
  .schedule-entry {
    width: 100%;
    text-align: left;
    background: transparent;
    padding: 0.2rem 0;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .entry-time-label {
    font-size: 0.76rem;
    font-weight: 550;
    color: var(--text-muted);
    letter-spacing: 0.02em;
    font-variant-numeric: tabular-nums;
    line-height: 1.2;
    margin-bottom: 0.05rem;
  }

  .time-end {
    opacity: 0.85;
    font-weight: 400;
  }

  .all-day-entry .entry-time-label {
    text-transform: uppercase;
    font-size: 0.68rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    color: var(--text-light);
  }

  .entry-title-row {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
  }

  .accent-bar {
    width: 2.5px;
    min-height: 1.15em;
    align-self: stretch;
    border-radius: 1px;
    flex-shrink: 0;
    opacity: 0.9;
  }

  .entry-title {
    font-size: 0.94rem;
    font-weight: 520;
    color: var(--text-main);
    line-height: 1.3;
    overflow-wrap: break-word;
    hyphens: auto;
  }

  .entry-meta {
    padding-left: calc(2.5px + 0.5rem);
    font-size: 0.8rem;
    font-weight: 400;
    color: var(--text-light);
    line-height: 1.25;
    overflow-wrap: break-word;
  }

  @media (max-width: 1366px) {
    .week-masthead {
      padding: 1rem 1.5rem 0.85rem 1.5rem;
    }
    .week-title {
      font-size: 1.7rem;
    }
    .day-column {
      padding: 0 0.55rem;
    }
    .day-header {
      padding: 0.9rem 0.25rem 0.65rem 0.25rem;
    }
    .day-name {
      font-size: 0.7rem;
    }
    .day-number {
      font-size: 1.4rem;
      width: 1.9rem;
      height: 1.9rem;
    }
    .day-number.active-today {
      font-size: 1rem;
      width: 1.7rem;
      height: 1.7rem;
    }
    .entry-title {
      font-size: 0.86rem;
    }
    .entry-time-label {
      font-size: 0.7rem;
    }
    .entry-meta {
      font-size: 0.74rem;
    }
  }
</style>

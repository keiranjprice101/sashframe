<script lang="ts">
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { getWeekDays, formatDateIso, isToday } from '../lib/dates';
  import { HOUSEHOLD_MEMBERS } from '../data/mock';

  interface Props {
    currentWeekStart: Date;
    events: CalendarEvent[];
    members?: Record<string, HouseholdMember>;
    onSelectEvent: (event: CalendarEvent) => void;
  }

  let { 
    currentWeekStart, 
    events, 
    members = HOUSEHOLD_MEMBERS, 
    onSelectEvent 
  }: Props = $props();

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

<div class="calendar-grid">
  {#each weekDays as day (day.toISOString())}
    {@const { allDay, timed } = getEventsForDay(day)}
    {@const todayClass = isToday(day)}

    <div class="day-column" class:is-today={todayClass}>
      <!-- Day Header: Unboxed, typographic, editorial -->
      <div class="day-header">
        <span class="day-name">{day.toLocaleDateString('en-US', { weekday: 'short' })}</span>
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
              <button 
                type="button" 
                class="schedule-entry all-day-entry"
                onclick={() => onSelectEvent(event)}
                aria-label="{event.title}, All day event for {member.name}"
              >
                <span class="entry-time-label">All day</span>
                <div class="entry-title-row">
                  <span class="accent-bar" style="background-color: var(--member-{event.memberId}, {member.color})"></span>
                  <span class="entry-title">{event.title}</span>
                </div>
                {#if event.location}
                  <span class="entry-meta">{event.location}</span>
                {/if}
              </button>
            {/each}
          </div>
        {/if}

        <!-- Timed Events Section -->
        <div class="timed-events-list">
          {#each timed as event (event.id)}
            {@const member = members[event.memberId] || members.alex}
            <button 
              type="button" 
              class="schedule-entry timed-entry"
              onclick={() => onSelectEvent(event)}
              aria-label="{event.title} at {event.startTime} for {member.name}"
            >
              <div class="entry-time-label">
                {event.startTime}
                {#if event.endTime}
                  <span class="time-end">– {event.endTime}</span>
                {/if}
              </div>
              <div class="entry-title-row">
                <span class="accent-bar" style="background-color: var(--member-{event.memberId}, {member.color})"></span>
                <span class="entry-title">{event.title}</span>
              </div>
              {#if event.location}
                <span class="entry-meta">{event.location}</span>
              {/if}
            </button>
          {/each}
        </div>
      </div>
    </div>
  {/each}
</div>

<style>
  .calendar-grid {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    height: 100%;
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
    padding: 0 0.75rem;
    border-right: 1px solid var(--border-hairline);
  }

  .day-column:last-child {
    border-right: none;
  }

  /* Day Header */
  .day-header {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    padding: 1.25rem 0.25rem 0.85rem 0.25rem;
    background: transparent;
    border-bottom: 1px solid var(--border-hairline);
    gap: 0.35rem;
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
    font-size: 1.75rem;
    font-weight: 400;
    color: var(--text-main);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .day-number.active-today {
    background-color: var(--accent-walnut);
    color: var(--accent-walnut-text);
    font-size: 1.2rem;
    font-weight: 500;
  }

  /* Day Body & Events */
  .day-body {
    flex: 1;
    display: flex;
    flex-direction: column;
    padding: 1.25rem 0.25rem 1.5rem 0.25rem;
    overflow-y: auto;
  }

  .all-day-section {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding-bottom: 1rem;
    margin-bottom: 1rem;
    border-bottom: 1px solid var(--border-hairline);
  }

  .timed-events-list {
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  /* Schedule Entry: Typeset schedule, not a card */
  .schedule-entry {
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    border-radius: var(--radius-sm);
    padding: 0.35rem 0.3rem;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    cursor: pointer;
    transition: background-color 0.15s ease, transform 0.1s ease;
    min-height: 48px; /* Touch-first accessibility */
  }

  .schedule-entry:hover {
    background-color: var(--control-hover);
  }

  .schedule-entry:focus-visible {
    outline: 2px solid var(--accent-walnut);
    outline-offset: 1px;
  }

  .schedule-entry:active {
    background-color: var(--control-hover);
    transform: scale(0.99);
  }

  .entry-time-label {
    font-size: 0.78rem;
    font-weight: 500;
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
    gap: 0.55rem;
  }

  .accent-bar {
    width: 2px;
    min-height: 1.15em;
    align-self: stretch;
    border-radius: 1px;
    flex-shrink: 0;
    opacity: 0.9;
  }

  .entry-title {
    font-size: 0.98rem;
    font-weight: 550;
    color: var(--text-main);
    line-height: 1.3;
    overflow-wrap: break-word;
    hyphens: auto;
  }

  .entry-meta {
    padding-left: calc(2px + 0.55rem);
    font-size: 0.82rem;
    font-weight: 400;
    color: var(--text-light);
    line-height: 1.25;
    overflow-wrap: break-word;
  }

  @media (max-width: 1366px) {
    .day-column {
      padding: 0 0.55rem;
    }
    .day-header {
      padding: 1rem 0.25rem 0.75rem 0.25rem;
    }
    .day-name {
      font-size: 0.72rem;
    }
    .day-number {
      font-size: 1.5rem;
      width: 2rem;
      height: 2rem;
    }
    .day-number.active-today {
      font-size: 1.1rem;
    }
    .entry-title {
      font-size: 0.92rem;
    }
    .entry-time-label {
      font-size: 0.74rem;
    }
    .entry-meta {
      font-size: 0.78rem;
    }
  }
</style>

<script lang="ts">
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { getWeekDays, formatDateIso, formatTime12h, isToday } from '../lib/dates';
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
      <!-- Day Header -->
      <div class="day-header">
        <span class="day-name">{day.toLocaleDateString('en-US', { weekday: 'short' })}</span>
        <div class="day-number-pill" class:active-today={todayClass}>
          {day.getDate()}
        </div>
      </div>

      <!-- Scrollable Day Content -->
      <div class="day-body">
        <!-- All-Day Events Section -->
        {#if allDay.length > 0}
          <div class="all-day-section">
            {#each allDay as event (event.id)}
              {@const member = members[event.memberId] || members.alex}
              <button 
                type="button" 
                class="event-card all-day-card"
                style="--member-color: {member.color}; --member-bg: {member.bgColor}; --member-border: {member.borderColor}; --member-text: {member.textColor}"
                onclick={() => onSelectEvent(event)}
                aria-label="{event.title}, All day event for {member.name}"
              >
                <span class="all-day-tag">ALL DAY</span>
                <span class="event-title">{event.title}</span>
                <span class="member-badge">{member.initials}</span>
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
              class="event-card timed-card"
              style="--member-color: {member.color}; --member-bg: {member.bgColor}; --member-border: {member.borderColor}; --member-text: {member.textColor}"
              onclick={() => onSelectEvent(event)}
              aria-label="{event.title} at {formatTime12h(event.startTime)} for {member.name}"
            >
              <div class="card-header">
                <span class="event-time">
                  {formatTime12h(event.startTime)}
                  {#if event.endTime}
                    – {formatTime12h(event.endTime)}
                  {/if}
                </span>
                <span class="member-badge" style="background-color: {member.color}; color: #ffffff;">
                  {member.initials}
                </span>
              </div>
              <div class="event-title">{event.title}</div>
              {#if event.location}
                <div class="event-location">📍 {event.location}</div>
              {/if}
            </button>
          {/each}

          {#if allDay.length === 0 && timed.length === 0}
            <div class="empty-day-placeholder">No events</div>
          {/if}
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
    background-color: var(--border-subtle);
    gap: 1px;
    overflow: hidden;
  }

  .day-column {
    display: flex;
    flex-direction: column;
    background-color: var(--bg-surface);
    height: 100%;
    overflow: hidden;
  }

  .day-column.is-today {
    background-color: var(--bg-surface-elevated);
  }

  .day-header {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 0.85rem 0.5rem;
    background-color: var(--bg-surface-elevated);
    border-bottom: 1px solid var(--border-subtle);
    gap: 0.25rem;
  }

  .day-name {
    font-size: 0.85rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
  }

  .day-number-pill {
    width: 2.3rem;
    height: 2.3rem;
    border-radius: var(--radius-full);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.15rem;
    font-weight: 700;
    color: var(--text-main);
  }

  .day-number-pill.active-today {
    background-color: var(--accent-walnut);
    color: #FFFFFF;
    box-shadow: 0 2px 6px rgba(74, 58, 49, 0.3);
  }

  .day-body {
    flex: 1;
    display: flex;
    flex-direction: column;
    padding: 0.6rem;
    gap: 0.6rem;
    overflow-y: auto;
  }

  .all-day-section {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    padding-bottom: 0.4rem;
    border-bottom: 1px stroke var(--border-subtle);
  }

  .timed-events-list {
    display: flex;
    flex-direction: column;
    gap: 0.6rem;
  }

  .event-card {
    text-align: left;
    width: 100%;
    padding: 0.75rem 0.85rem;
    border-radius: var(--radius-md);
    background-color: var(--member-bg);
    border-left: 4px solid var(--member-color);
    border-top: 1px solid var(--member-border);
    border-right: 1px solid var(--member-border);
    border-bottom: 1px solid var(--member-border);
    box-shadow: var(--shadow-subtle);
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    transition: transform 0.12s ease, box-shadow 0.12s ease;
    cursor: pointer;
    min-height: 56px;
  }

  .event-card:active {
    transform: scale(0.97);
    box-shadow: none;
  }

  .all-day-card {
    background-color: var(--member-color);
    color: #FFFFFF;
    border: none;
    padding: 0.5rem 0.75rem;
    position: relative;
  }

  .all-day-tag {
    font-size: 0.65rem;
    font-weight: 800;
    letter-spacing: 0.06em;
    opacity: 0.85;
  }

  .all-day-card .event-title {
    color: #FFFFFF;
    font-size: 0.95rem;
    font-weight: 700;
  }

  .all-day-card .member-badge {
    position: absolute;
    top: 0.4rem;
    right: 0.4rem;
    background: rgba(255, 255, 255, 0.25);
    color: #FFFFFF;
  }

  .card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.4rem;
  }

  .event-time {
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--member-text);
  }

  .member-badge {
    font-size: 0.7rem;
    font-weight: 700;
    padding: 0.15rem 0.4rem;
    border-radius: var(--radius-full);
    line-height: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .event-title {
    font-size: 0.95rem;
    font-weight: 600;
    color: var(--text-main);
    line-height: 1.25;
    word-break: break-word;
  }

  .event-location {
    font-size: 0.75rem;
    color: var(--text-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .empty-day-placeholder {
    padding: 1.5rem 0.5rem;
    text-align: center;
    font-size: 0.8rem;
    color: var(--text-light);
    font-style: italic;
  }

  @media (max-width: 1366px) {
    .day-header {
      padding: 0.6rem 0.3rem;
    }
    .day-name {
      font-size: 0.75rem;
    }
    .day-number-pill {
      width: 1.9rem;
      height: 1.9rem;
      font-size: 1rem;
    }
    .event-card {
      padding: 0.6rem 0.65rem;
    }
    .event-title {
      font-size: 0.85rem;
    }
    .event-time {
      font-size: 0.75rem;
    }
  }
</style>

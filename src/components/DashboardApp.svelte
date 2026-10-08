<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import PhotoPanel from './PhotoPanel.svelte';
  import CalendarMonth from './CalendarMonth.svelte';
  import CalendarWeek from './CalendarWeek.svelte';

  import type { CalendarEvent } from '../lib/types';
  import { getAutomaticTheme } from '../lib/sunSchedule';
  import { HOUSEHOLD_MEMBERS, MOCK_PHOTOS, MOCK_WEATHER, getInitialMockEvents } from '../data/mock';

  interface Props {
    initialShifterEvents?: CalendarEvent[];
  }

  let { initialShifterEvents = [] }: Props = $props();

  function resolveCalendarEvents(shifterList: CalendarEvent[]): CalendarEvent[] {
    // If real Shifter events are loaded, display only real calendar data.
    // Mock events serve purely as an initial placeholder when no Shifter file is present.
    if (shifterList.length > 0) {
      return shifterList;
    }
    return getInitialMockEvents();
  }

  // svelte-ignore state_referenced_locally
  let events = $state<CalendarEvent[]>(resolveCalendarEvents(initialShifterEvents));
  let theme = $state<'light' | 'dark'>(getAutomaticTheme());
  let currentView = $state<'month' | 'week'>('week');

  let solarTimer: ReturnType<typeof setInterval>;
  let viewTimer: ReturnType<typeof setInterval>;
  let calendarTimer: ReturnType<typeof setInterval>;

  async function refreshCalendarEvents() {
    try {
      const res = await fetch('/api/calendar');
      if (!res.ok) return;
      const data: CalendarEvent[] = await res.json();
      if (Array.isArray(data)) {
        events = resolveCalendarEvents(data);
      }
    } catch {
      // Ignore network errors in local dev
    }
  }

  onMount(() => {
    // Initial evaluation of solar theme
    theme = getAutomaticTheme(new Date());
    document.documentElement.setAttribute('data-theme', theme);

    // If client mounted without initial shifter events, fetch immediately
    if (initialShifterEvents.length === 0) {
      refreshCalendarEvents();
    }

    // Periodically poll Shifter calendar endpoint every 30 seconds
    calendarTimer = setInterval(refreshCalendarEvents, 30000);

    // Periodically re-evaluate every 30 seconds for sunrise/sunset transitions
    solarTimer = setInterval(() => {
      const current = getAutomaticTheme(new Date());
      if (current !== theme) {
        theme = current;
        document.documentElement.setAttribute('data-theme', theme);
      }
    }, 30000);

    // Smoothly cycle between week view and month view every 60 seconds
    viewTimer = setInterval(() => {
      currentView = currentView === 'month' ? 'week' : 'month';
    }, 60000);
  });

  onDestroy(() => {
    if (solarTimer) clearInterval(solarTimer);
    if (viewTimer) clearInterval(viewTimer);
    if (calendarTimer) clearInterval(calendarTimer);
  });
</script>

<div class="kiosk-dashboard">
  <!-- Photo Panel (Left side, ~40% width) -->
  <PhotoPanel 
    photos={MOCK_PHOTOS} 
    weather={MOCK_WEATHER} 
    rotationIntervalMs={60000} 
  />

  <!-- Calendar Panel (Right side, taking up entirety of right side) -->
  <div class="calendar-panel">
    <div class="view-viewport">
      <div 
        class="view-layer" 
        class:is-active={currentView === 'month'} 
        class:is-hidden={currentView !== 'month'}
        aria-hidden={currentView !== 'month'}
      >
        <CalendarMonth 
          {events}
          members={HOUSEHOLD_MEMBERS}
        />
      </div>

      <div 
        class="view-layer" 
        class:is-active={currentView === 'week'} 
        class:is-hidden={currentView !== 'week'}
        aria-hidden={currentView !== 'week'}
      >
        <CalendarWeek 
          {events}
          members={HOUSEHOLD_MEMBERS}
        />
      </div>
    </div>
  </div>
</div>

<style>
  .kiosk-dashboard {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: row;
    overflow: hidden;
    background-color: var(--bg-app);
  }

  .calendar-panel {
    flex: 1;
    height: 100%;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background-color: var(--bg-surface);
    position: relative;
  }

  .view-viewport {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
  }

  .view-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    transition: opacity 0.8s cubic-bezier(0.4, 0, 0.2, 1), transform 0.8s cubic-bezier(0.4, 0, 0.2, 1);
    will-change: opacity, transform;
  }

  .view-layer.is-active {
    opacity: 1;
    transform: scale(1);
    pointer-events: auto;
    z-index: 2;
  }

  .view-layer.is-hidden {
    opacity: 0;
    transform: scale(0.994);
    pointer-events: none;
    z-index: 1;
  }
</style>

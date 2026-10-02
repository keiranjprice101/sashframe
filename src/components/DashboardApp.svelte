<script lang="ts">
  import PhotoPanel from './PhotoPanel.svelte';
  import DateNavigation from './DateNavigation.svelte';
  import CalendarWeek from './CalendarWeek.svelte';
  import EventModal from './EventModal.svelte';
  import AddEventModal from './AddEventModal.svelte';

  import type { CalendarEvent } from '../lib/types';
  import { getStartOfWeek, addWeeks, formatDateIso } from '../lib/dates';
  import { HOUSEHOLD_MEMBERS, MOCK_PHOTOS, MOCK_WEATHER, getInitialMockEvents } from '../data/mock';

  let currentWeekStart = $state(getStartOfWeek(new Date()));
  let events = $state<CalendarEvent[]>(getInitialMockEvents());
  let selectedEvent = $state<CalendarEvent | null>(null);
  let isAddModalOpen = $state(false);

  function handlePrevWeek() {
    currentWeekStart = addWeeks(currentWeekStart, -1);
  }

  function handleNextWeek() {
    currentWeekStart = addWeeks(currentWeekStart, 1);
  }

  function handleToday() {
    currentWeekStart = getStartOfWeek(new Date());
  }

  function handleSelectEvent(event: CalendarEvent) {
    selectedEvent = event;
  }

  function handleCloseEventModal() {
    selectedEvent = null;
  }

  function handleDeleteEvent(eventId: string) {
    events = events.filter(e => e.id !== eventId);
    selectedEvent = null;
  }

  function handleOpenAddModal() {
    isAddModalOpen = true;
  }

  function handleCloseAddModal() {
    isAddModalOpen = false;
  }

  function handleSaveNewEvent(newEvent: CalendarEvent) {
    events = [...events, newEvent];
  }
</script>

<div class="kiosk-dashboard">
  <!-- Photo Panel (Left side, ~40% width) -->
  <PhotoPanel 
    photos={MOCK_PHOTOS} 
    weather={MOCK_WEATHER} 
    rotationIntervalMs={60000} 
  />

  <!-- Calendar Panel (Right side, ~60% width) -->
  <div class="calendar-panel">
    <DateNavigation 
      {currentWeekStart}
      onPrevWeek={handlePrevWeek}
      onNextWeek={handleNextWeek}
      onToday={handleToday}
      onAddEvent={handleOpenAddModal}
    />

    <div class="week-view-container">
      <CalendarWeek 
        {currentWeekStart}
        {events}
        members={HOUSEHOLD_MEMBERS}
        onSelectEvent={handleSelectEvent}
      />
    </div>
  </div>

  <!-- Event Details Modal -->
  <EventModal 
    event={selectedEvent}
    members={HOUSEHOLD_MEMBERS}
    onClose={handleCloseEventModal}
    onDelete={handleDeleteEvent}
  />

  <!-- Add Event Modal -->
  <AddEventModal 
    isOpen={isAddModalOpen}
    defaultDate={formatDateIso(new Date())}
    members={HOUSEHOLD_MEMBERS}
    onClose={handleCloseAddModal}
    onSave={handleSaveNewEvent}
  />
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
  }

  .week-view-container {
    flex: 1;
    min-height: 0;
    overflow: hidden;
    position: relative;
  }
</style>

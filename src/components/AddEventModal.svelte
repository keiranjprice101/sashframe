<script lang="ts">
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { formatDateIso } from '../lib/dates';
  import { HOUSEHOLD_MEMBERS } from '../data/mock';

  interface Props {
    isOpen: boolean;
    defaultDate?: string;
    members?: Record<string, HouseholdMember>;
    onClose: () => void;
    onSave: (newEvent: CalendarEvent) => void;
  }

  let { 
    isOpen, 
    defaultDate = formatDateIso(new Date()), 
    members = HOUSEHOLD_MEMBERS, 
    onClose, 
    onSave 
  }: Props = $props();

  let title = $state('');
  let memberId = $state('alex');
  let date = $state(defaultDate);
  let isAllDay = $state(false);
  let startTime = $state('10:00');
  let endTime = $state('11:00');
  let description = $state('');
  let location = $state('');

  let errorMsg = $state<string | null>(null);

  // Sync defaultDate when modal opens
  $effect(() => {
    if (isOpen) {
      date = defaultDate;
    }
  });

  function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    if (!title.trim()) {
      errorMsg = 'Please enter an event title.';
      return;
    }

    const newEvent: CalendarEvent = {
      id: `custom-event-${Date.now()}`,
      title: title.trim(),
      memberId,
      date,
      isAllDay,
      startTime: isAllDay ? undefined : startTime,
      endTime: isAllDay ? undefined : endTime,
      location: location.trim() || undefined,
      description: description.trim() || undefined
    };

    onSave(newEvent);

    // Reset form & close
    title = '';
    description = '';
    location = '';
    errorMsg = null;
    onClose();
  }
</script>

{#if isOpen}
  <!-- Backdrop -->
  <div 
    class="modal-backdrop"
    onclick={onClose}
    role="button"
    tabindex="-1"
    aria-label="Close add event modal background"
  >
    <!-- Container -->
    <div 
      class="modal-container animate-fade-in"
      onclick={(e) => e.stopPropagation()}
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-modal-title"
    >
      <div class="modal-header">
        <h3 id="add-modal-title" class="header-title">Add New Event</h3>
        <button type="button" class="close-btn" onclick={onClose} aria-label="Close">✕</button>
      </div>

      <form class="modal-form" onsubmit={handleSubmit}>
        <div class="form-body">
          {#if errorMsg}
            <div class="error-banner">{errorMsg}</div>
          {/if}

          <!-- Title Input -->
          <div class="form-group">
            <label for="event-title">Event Title</label>
            <input 
              id="event-title"
              type="text" 
              class="input-touch" 
              placeholder="e.g. Work Meeting, Dinner, Dentist..." 
              bind:value={title}
              required
            />
          </div>

          <!-- Member Selector (Pill options) -->
          <div class="form-group">
            <label for="member-select">For Household Member</label>
            <div id="member-select" class="member-selector">
              {#each Object.values(members) as m (m.id)}
                <button 
                  type="button"
                  class="member-pill"
                  class:selected={memberId === m.id}
                  style="--m-color: {m.color}; --m-bg: {m.bgColor}"
                  onclick={() => memberId = m.id}
                >
                  <span class="pill-dot" style="background-color: {m.color}"></span>
                  {m.name}
                </button>
              {/each}
            </div>
          </div>

          <!-- Date & All-Day Toggle -->
          <div class="form-row">
            <div class="form-group flex-1">
              <label for="event-date">Date</label>
              <input 
                id="event-date"
                type="date" 
                class="input-touch"
                bind:value={date}
                required
              />
            </div>

            <div class="form-group checkbox-group">
              <label class="checkbox-label" for="all-day-checkbox">
                <input 
                  id="all-day-checkbox"
                  type="checkbox" 
                  class="checkbox-touch"
                  bind:checked={isAllDay}
                />
                <span>All Day Event</span>
              </label>
            </div>
          </div>

          <!-- Times (if not all day) -->
          {#if !isAllDay}
            <div class="form-row">
              <div class="form-group flex-1">
                <label for="start-time">Start Time</label>
                <input 
                  id="start-time"
                  type="time" 
                  class="input-touch"
                  bind:value={startTime}
                />
              </div>

              <div class="form-group flex-1">
                <label for="end-time">End Time</label>
                <input 
                  id="end-time"
                  type="time" 
                  class="input-touch"
                  bind:value={endTime}
                />
              </div>
            </div>
          {/if}

          <!-- Location -->
          <div class="form-group">
            <label for="event-location">Location (Optional)</label>
            <input 
              id="event-location"
              type="text" 
              class="input-touch"
              placeholder="e.g. Kitchen, Downtown, Remote"
              bind:value={location}
            />
          </div>

          <!-- Notes -->
          <div class="form-group">
            <label for="event-description">Notes & Details (Optional)</label>
            <textarea 
              id="event-description"
              class="input-touch textarea-touch"
              rows="2"
              placeholder="Add additional details..."
              bind:value={description}
            ></textarea>
          </div>
        </div>

        <div class="modal-footer">
          <button type="button" class="btn-secondary" onclick={onClose}>
            Cancel
          </button>
          <button type="submit" class="btn-primary">
            Save Event
          </button>
        </div>
      </form>
    </div>
  </div>
{/if}

<style>
  .modal-backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background-color: rgba(20, 16, 14, 0.65);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1.5rem;
  }

  .modal-container {
    background-color: var(--bg-surface);
    width: 100%;
    max-width: 560px;
    max-height: 90vh;
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-modal);
    border: 1px solid var(--border-subtle);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.25rem 1.5rem;
    background-color: var(--bg-surface-elevated);
    border-bottom: 1px solid var(--border-subtle);
  }

  .header-title {
    font-size: 1.35rem;
    font-weight: 700;
    color: var(--text-main);
  }

  .close-btn {
    width: 44px;
    height: 44px;
    border-radius: var(--radius-full);
    font-size: 1.2rem;
    color: var(--text-muted);
  }

  .modal-form {
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }

  .form-body {
    padding: 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1.2rem;
  }

  .error-banner {
    padding: 0.75rem 1rem;
    background-color: #FEE2E2;
    color: #991B1B;
    border-radius: var(--radius-sm);
    font-size: 0.9rem;
    font-weight: 600;
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .form-group label {
    font-size: 0.9rem;
    font-weight: 700;
    color: var(--text-main);
  }

  .form-row {
    display: flex;
    gap: 1rem;
    align-items: flex-end;
  }

  .flex-1 {
    flex: 1;
  }

  .input-touch {
    width: 100%;
    min-height: 48px;
    padding: 0.75rem 1rem;
    font-size: 1rem;
    font-family: inherit;
    border-radius: var(--radius-md);
    border: 1px solid var(--border-strong);
    background-color: var(--bg-surface-elevated);
    color: var(--text-main);
    outline: none;
  }

  .input-touch:focus {
    border-color: var(--accent-walnut);
    box-shadow: 0 0 0 3px rgba(74, 58, 49, 0.15);
  }

  .textarea-touch {
    min-height: 72px;
    resize: vertical;
  }

  .member-selector {
    display: flex;
    gap: 0.75rem;
  }

  .member-pill {
    flex: 1;
    min-height: 48px;
    border-radius: var(--radius-md);
    border: 2px solid var(--border-subtle);
    background-color: var(--bg-surface-alt);
    color: var(--text-main);
    font-size: 1rem;
    font-weight: 600;
    gap: 0.5rem;
  }

  .member-pill.selected {
    border-color: var(--m-color);
    background-color: var(--m-bg);
    color: var(--text-main);
  }

  .pill-dot {
    width: 12px;
    height: 12px;
    border-radius: var(--radius-full);
  }

  .checkbox-group {
    justify-content: center;
    padding-bottom: 0.5rem;
  }

  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 600;
  }

  .checkbox-touch {
    width: 24px;
    height: 24px;
    accent-color: var(--accent-walnut);
  }

  .modal-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 0.75rem;
    padding: 1.25rem 1.5rem;
    background-color: var(--bg-surface-elevated);
    border-top: 1px solid var(--border-subtle);
  }

  .btn-secondary {
    min-height: 48px;
    padding: 0 1.25rem;
    border-radius: var(--radius-md);
    background-color: var(--bg-surface-alt);
    border: 1px solid var(--border-subtle);
    font-weight: 600;
    font-size: 1rem;
    color: var(--text-main);
  }

  .btn-primary {
    min-height: 48px;
    padding: 0 1.5rem;
    border-radius: var(--radius-md);
    background-color: var(--accent-walnut);
    color: #FFFFFF;
    font-weight: 600;
    font-size: 1rem;
  }

  .btn-primary:active {
    background-color: var(--accent-walnut-hover);
  }
</style>

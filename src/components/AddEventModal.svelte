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
        <h3 id="add-modal-title" class="header-title">New Event</h3>
        <button 
          type="button" 
          class="close-btn" 
          onclick={onClose} 
          aria-label="Close"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>
      </div>

      <form class="modal-form" onsubmit={handleSubmit}>
        <div class="form-body">
          {#if errorMsg}
            <div class="error-banner">{errorMsg}</div>
          {/if}

          <!-- Member Selector (Subtle dots) -->
          <div class="form-group">
            <span class="field-label">Calendar</span>
            <div class="member-selector">
              {#each Object.values(members) as m (m.id)}
                <button 
                  type="button"
                  class="member-pill"
                  class:selected={memberId === m.id}
                  style="--m-color: var(--member-{m.id}, {m.color});"
                  onclick={() => memberId = m.id}
                >
                  <span class="pill-dot" style="background-color: var(--member-{m.id}, {m.color});"></span>
                  <span class="pill-name">{m.name}</span>
                </button>
              {/each}
            </div>
          </div>

          <!-- Title Input -->
          <div class="form-group">
            <label for="event-title" class="field-label">Title</label>
            <input 
              id="event-title"
              type="text" 
              class="input-touch" 
              placeholder="Event name" 
              bind:value={title}
              required
            />
          </div>

          <!-- Date & All-Day Toggle -->
          <div class="form-row">
            <div class="form-group flex-1">
              <label for="event-date" class="field-label">Date</label>
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
                <span>All Day</span>
              </label>
            </div>
          </div>

          <!-- Times (if not all day) -->
          {#if !isAllDay}
            <div class="form-row">
              <div class="form-group flex-1">
                <label for="start-time" class="field-label">Start</label>
                <input 
                  id="start-time"
                  type="time" 
                  class="input-touch" 
                  bind:value={startTime}
                />
              </div>

              <div class="form-group flex-1">
                <label for="end-time" class="field-label">End</label>
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
            <label for="event-location" class="field-label">Location</label>
            <input 
              id="event-location"
              type="text" 
              class="input-touch" 
              placeholder="e.g. Studio, Home, Downtown (optional)" 
              bind:value={location}
            />
          </div>

          <!-- Notes -->
          <div class="form-group">
            <label for="event-description" class="field-label">Notes</label>
            <textarea 
              id="event-description"
              class="input-touch textarea-touch" 
              rows="2"
              placeholder="Additional details (optional)" 
              bind:value={description}
            ></textarea>
          </div>
        </div>

        <div class="modal-footer">
          <button type="button" class="btn-secondary" onclick={onClose}>
            Cancel
          </button>
          <button type="submit" class="btn-primary">
            Save
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
    background-color: var(--modal-backdrop);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1.5rem;
  }

  .modal-container {
    background-color: var(--bg-surface);
    width: 100%;
    max-width: 500px;
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
    padding: 1.25rem 1.5rem 0.85rem 1.5rem;
    border-bottom: 1px solid var(--border-hairline);
  }

  .header-title {
    font-size: 1.35rem;
    font-weight: 500;
    color: var(--text-main);
    letter-spacing: -0.01em;
  }

  .close-btn {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-sm);
    color: var(--text-muted);
    background: transparent;
    transition: background-color 0.15s ease, color 0.15s ease;
  }

  .close-btn:hover {
    background-color: var(--control-hover);
    color: var(--text-main);
  }

  .close-btn:active {
    background-color: var(--control-hover);
    color: var(--text-main);
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
    gap: 1.1rem;
  }

  .error-banner {
    padding: 0.65rem 0.85rem;
    background-color: var(--danger-bg);
    color: var(--danger-text);
    border-radius: var(--radius-sm);
    font-size: 0.88rem;
    font-weight: 500;
    border: 1px solid var(--danger-border);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .field-label {
    font-size: 0.76rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
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
    min-height: 46px;
    padding: 0.65rem 0.85rem;
    font-size: 0.96rem;
    font-family: inherit;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-subtle);
    background-color: var(--bg-surface-elevated);
    color: var(--text-main);
    outline: none;
    transition: border-color 0.15s ease, box-shadow 0.15s ease;
  }

  .input-touch:focus {
    border-color: var(--accent-walnut);
    box-shadow: 0 0 0 2px var(--control-hover);
  }

  .textarea-touch {
    min-height: 68px;
    resize: vertical;
  }

  .member-selector {
    display: flex;
    gap: 0.65rem;
  }

  .member-pill {
    flex: 1;
    min-height: 44px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-subtle);
    background-color: var(--bg-surface-elevated);
    color: var(--text-muted);
    font-size: 0.92rem;
    font-weight: 500;
    gap: 0.5rem;
    transition: border-color 0.15s ease, background-color 0.15s ease, color 0.15s ease;
  }

  .member-pill.selected {
    border-color: var(--m-color);
    background-color: var(--bg-surface);
    color: var(--text-main);
  }

  .pill-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
  }

  .checkbox-group {
    justify-content: center;
    padding-bottom: 0.35rem;
  }

  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: none;
    font-size: 0.92rem;
    font-weight: 500;
    color: var(--text-main);
  }

  .checkbox-touch {
    width: 20px;
    height: 20px;
    accent-color: var(--accent-walnut);
  }

  .modal-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 0.75rem;
    padding: 1.15rem 1.5rem;
    background-color: var(--bg-surface-elevated);
    border-top: 1px solid var(--border-hairline);
  }

  .btn-secondary {
    min-height: 44px;
    padding: 0 1.15rem;
    border-radius: var(--radius-sm);
    background-color: var(--bg-surface);
    border: 1px solid var(--border-subtle);
    font-weight: 500;
    font-size: 0.92rem;
    color: var(--text-main);
    transition: background-color 0.15s ease, border-color 0.15s ease;
  }

  .btn-secondary:hover {
    background-color: var(--bg-surface-elevated);
    border-color: var(--border-strong);
  }

  .btn-secondary:active {
    background-color: var(--border-subtle);
  }

  .btn-primary {
    min-height: 44px;
    padding: 0 1.35rem;
    border-radius: var(--radius-sm);
    background-color: var(--accent-walnut);
    color: var(--accent-walnut-text);
    font-weight: 500;
    font-size: 0.92rem;
    transition: background-color 0.15s ease;
  }

  .btn-primary:hover {
    background-color: var(--accent-walnut-hover);
  }

  .btn-primary:active {
    background-color: var(--accent-walnut-hover);
  }
</style>

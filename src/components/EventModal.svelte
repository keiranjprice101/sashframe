<script lang="ts">
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { formatDisplayDate } from '../lib/dates';
  import { HOUSEHOLD_MEMBERS } from '../data/mock';

  interface Props {
    event: CalendarEvent | null;
    members?: Record<string, HouseholdMember>;
    onClose: () => void;
    onDelete?: (eventId: string) => void;
  }

  let { 
    event, 
    members = HOUSEHOLD_MEMBERS, 
    onClose,
    onDelete 
  }: Props = $props();

  let member = $derived(event ? members[event.memberId] || members.alex : null);
  let formattedDate = $derived(event ? formatDisplayDate(new Date(event.date + 'T00:00:00')) : '');
  
  let notificationMsg = $state<string | null>(null);

  function handleEdit() {
    notificationMsg = "Edit action triggered (Placeholder for MVP)";
    setTimeout(() => {
      notificationMsg = null;
    }, 2500);
  }

  function handleDelete() {
    if (event && onDelete) {
      onDelete(event.id);
      onClose();
    } else {
      notificationMsg = "Delete action triggered (Placeholder for MVP)";
      setTimeout(() => {
        notificationMsg = null;
      }, 2500);
    }
  }
</script>

{#if event && member}
  <!-- Backdrop -->
  <div 
    class="modal-backdrop"
    onclick={onClose}
    role="button"
    tabindex="-1"
    aria-label="Close modal background"
  >
    <!-- Modal Container -->
    <div 
      class="modal-container animate-fade-in"
      onclick={(e) => e.stopPropagation()}
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
    >
      <!-- Header -->
      <div class="modal-header">
        <div class="member-indicator">
          <span class="member-dot" style="background-color: var(--member-{event.memberId}, {member.color});"></span>
          <span class="member-name">{member.name}</span>
        </div>
        <button 
          type="button" 
          class="close-btn" 
          onclick={onClose}
          aria-label="Close modal"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>
      </div>

      <!-- Content -->
      <div class="modal-body">
        <h3 id="modal-title" class="event-title">{event.title}</h3>

        <div class="meta-grid">
          <div class="meta-item">
            <span class="meta-label">Date</span>
            <span class="meta-value">{formattedDate}</span>
          </div>

          <div class="meta-item">
            <span class="meta-label">Time</span>
            <span class="meta-value">
              {#if event.isAllDay}
                All Day
              {:else}
                {event.startTime}{event.endTime ? ` – ${event.endTime}` : ''}
              {/if}
            </span>
          </div>

          {#if event.location}
            <div class="meta-item">
              <span class="meta-label">Location</span>
              <span class="meta-value">{event.location}</span>
            </div>
          {/if}
        </div>

        {#if event.description}
          <div class="notes-section">
            <div class="notes-label">Notes</div>
            <div class="notes-text">{event.description}</div>
          </div>
        {/if}

        {#if notificationMsg}
          <div class="toast-notification animate-fade-in">
            {notificationMsg}
          </div>
        {/if}
      </div>

      <!-- Action Footer -->
      <div class="modal-footer">
        <button 
          type="button" 
          class="btn-delete" 
          onclick={handleDelete}
        >
          Delete
        </button>

        <div class="right-actions">
          <button 
            type="button" 
            class="btn-secondary" 
            onclick={handleEdit}
          >
            Edit
          </button>

          <button 
            type="button" 
            class="btn-primary" 
            onclick={onClose}
          >
            Done
          </button>
        </div>
      </div>
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
    max-width: 480px;
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

  .member-indicator {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .member-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
  }

  .member-name {
    font-size: 0.88rem;
    font-weight: 500;
    color: var(--text-muted);
    letter-spacing: 0.02em;
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

  .modal-body {
    padding: 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .event-title {
    font-size: 1.45rem;
    font-weight: 500;
    color: var(--text-main);
    line-height: 1.3;
    letter-spacing: -0.01em;
  }

  .meta-grid {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    border-top: 1px solid var(--border-hairline);
    padding-top: 1rem;
  }

  .meta-item {
    display: grid;
    grid-template-columns: 80px 1fr;
    align-items: baseline;
    gap: 0.75rem;
  }

  .meta-label {
    font-size: 0.8rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
  }

  .meta-value {
    font-size: 0.95rem;
    color: var(--text-main);
    line-height: 1.35;
  }

  .notes-section {
    padding: 0.85rem 1rem;
    background-color: var(--bg-surface-elevated);
    border-radius: var(--radius-sm);
    border: 1px solid var(--border-hairline);
  }

  .notes-label {
    font-size: 0.75rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
    margin-bottom: 0.3rem;
  }

  .notes-text {
    font-size: 0.9rem;
    color: var(--text-main);
    line-height: 1.4;
  }

  .toast-notification {
    padding: 0.65rem 0.85rem;
    background-color: var(--accent-warm-highlight);
    color: var(--accent-walnut);
    font-weight: 500;
    font-size: 0.9rem;
    border-radius: var(--radius-sm);
    text-align: center;
  }

  .modal-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.15rem 1.5rem;
    border-top: 1px solid var(--border-hairline);
    background-color: var(--bg-surface-elevated);
  }

  .right-actions {
    display: flex;
    align-items: center;
    gap: 0.65rem;
  }

  .btn-delete {
    min-height: 44px;
    padding: 0 0.85rem;
    font-size: 0.9rem;
    font-weight: 500;
    color: var(--danger-text);
    border-radius: var(--radius-sm);
    background: transparent;
    transition: background-color 0.15s ease, color 0.15s ease;
  }

  .btn-delete:hover {
    background-color: var(--danger-bg);
  }

  .btn-delete:active {
    background-color: var(--danger-bg);
  }

  .btn-secondary {
    min-height: 44px;
    padding: 0 1.15rem;
    font-size: 0.92rem;
    font-weight: 500;
    color: var(--text-main);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-sm);
    background-color: var(--bg-surface);
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
    font-size: 0.92rem;
    font-weight: 500;
    color: var(--accent-walnut-text);
    background-color: var(--accent-walnut);
    border-radius: var(--radius-sm);
    transition: background-color 0.15s ease;
  }

  .btn-primary:hover {
    background-color: var(--accent-walnut-hover);
  }

  .btn-primary:active {
    background-color: var(--accent-walnut-hover);
  }
</style>

<script lang="ts">
  import type { CalendarEvent, HouseholdMember } from '../lib/types';
  import { formatDisplayDate, formatTime12h } from '../lib/dates';
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
        <div class="member-tag" style="background-color: {member.color};">
          {member.name}
        </div>
        <button 
          type="button" 
          class="close-btn touch-target" 
          onclick={onClose}
          aria-label="Close modal"
        >
          ✕
        </button>
      </div>

      <!-- Content -->
      <div class="modal-body">
        <h3 id="modal-title" class="event-title">{event.title}</h3>

        <div class="detail-row">
          <span class="icon">📅</span>
          <span class="detail-text">{formattedDate}</span>
        </div>

        <div class="detail-row">
          <span class="icon">⏰</span>
          <span class="detail-text">
            {#if event.isAllDay}
              All-Day Event
            {:else}
              {formatTime12h(event.startTime)}
              {#if event.endTime}
                – {formatTime12h(event.endTime)}
              {/if}
            {/if}
          </span>
        </div>

        {#if event.location}
          <div class="detail-row">
            <span class="icon">📍</span>
            <span class="detail-text">{event.location}</span>
          </div>
        {/if}

        {#if event.description}
          <div class="notes-box">
            <div class="notes-label">Notes & Details</div>
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
          class="action-btn delete-btn" 
          onclick={handleDelete}
        >
          🗑️ Delete
        </button>

        <button 
          type="button" 
          class="action-btn edit-btn" 
          onclick={handleEdit}
        >
          ✏️ Edit
        </button>

        <button 
          type="button" 
          class="action-btn close-action-btn" 
          onclick={onClose}
        >
          Close
        </button>
      </div>
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
    max-width: 520px;
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

  .member-tag {
    color: #FFFFFF;
    font-size: 0.9rem;
    font-weight: 700;
    padding: 0.35rem 1rem;
    border-radius: var(--radius-full);
    letter-spacing: 0.02em;
  }

  .close-btn {
    width: 44px;
    height: 44px;
    border-radius: var(--radius-full);
    font-size: 1.2rem;
    color: var(--text-muted);
  }

  .close-btn:active {
    background-color: var(--border-subtle);
  }

  .modal-body {
    padding: 1.75rem 1.5rem;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .event-title {
    font-size: 1.65rem;
    font-weight: 700;
    color: var(--text-main);
    line-height: 1.25;
    margin-bottom: 0.5rem;
  }

  .detail-row {
    display: flex;
    align-items: center;
    gap: 0.85rem;
    font-size: 1.1rem;
    color: var(--text-main);
  }

  .icon {
    font-size: 1.25rem;
  }

  .notes-box {
    margin-top: 0.5rem;
    padding: 1rem;
    background-color: var(--bg-surface-alt);
    border-radius: var(--radius-md);
    border: 1px solid var(--border-subtle);
  }

  .notes-label {
    font-size: 0.8rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-muted);
    margin-bottom: 0.3rem;
  }

  .notes-text {
    font-size: 0.95rem;
    color: var(--text-main);
    line-height: 1.4;
  }

  .toast-notification {
    padding: 0.75rem 1rem;
    background-color: var(--accent-warm-highlight);
    color: var(--accent-walnut);
    font-weight: 600;
    font-size: 0.95rem;
    border-radius: var(--radius-sm);
    text-align: center;
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

  .action-btn {
    min-height: 48px;
    padding: 0 1.25rem;
    border-radius: var(--radius-md);
    font-weight: 600;
    font-size: 1rem;
  }

  .delete-btn {
    margin-right: auto;
    background-color: #FEE2E2;
    color: #991B1B;
  }

  .delete-btn:active {
    background-color: #FCA5A5;
  }

  .edit-btn {
    background-color: var(--bg-surface-alt);
    color: var(--text-main);
    border: 1px solid var(--border-subtle);
  }

  .edit-btn:active {
    background-color: var(--border-subtle);
  }

  .close-action-btn {
    background-color: var(--accent-walnut);
    color: #FFFFFF;
  }

  .close-action-btn:active {
    background-color: var(--accent-walnut-hover);
  }
</style>

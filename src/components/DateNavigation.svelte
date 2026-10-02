<script lang="ts">
  import { formatDayShort, addDays } from '../lib/dates';

  interface Props {
    currentWeekStart: Date;
    onPrevWeek: () => void;
    onNextWeek: () => void;
    onToday: () => void;
    onAddEvent: () => void;
  }

  let { currentWeekStart, onPrevWeek, onNextWeek, onToday, onAddEvent }: Props = $props();

  let weekEnd = $derived(addDays(currentWeekStart, 6));

  let formattedRange = $derived.by(() => {
    const startStr = `${formatDayShort(currentWeekStart)}, ${currentWeekStart.toLocaleString('en-US', { month: 'short', day: 'numeric' })}`;
    const endStr = `${formatDayShort(weekEnd)}, ${weekEnd.toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`;
    return `${startStr} – ${endStr}`;
  });
</script>

<div class="nav-bar">
  <div class="week-title-container">
    <h2 class="week-range-text">{formattedRange}</h2>
  </div>

  <div class="controls-container">
    <div class="nav-group">
      <button 
        type="button" 
        class="touch-btn nav-arrow" 
        onclick={onPrevWeek} 
        aria-label="Previous Week"
      >
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="15 18 9 12 15 6"></polyline>
        </svg>
      </button>

      <button 
        type="button" 
        class="touch-btn today-btn" 
        onclick={onToday}
      >
        Today
      </button>

      <button 
        type="button" 
        class="touch-btn nav-arrow" 
        onclick={onNextWeek} 
        aria-label="Next Week"
      >
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="9 18 15 12 9 6"></polyline>
        </svg>
      </button>
    </div>

    <button 
      type="button" 
      class="touch-btn add-event-btn" 
      onclick={onAddEvent}
      aria-label="Add New Event"
    >
      <span class="plus-icon">+</span>
      <span class="btn-text">Add Event</span>
    </button>
  </div>
</div>

<style>
  .nav-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.25rem 1.75rem;
    background-color: var(--bg-surface-elevated);
    border-bottom: 1px solid var(--border-subtle);
    flex-shrink: 0;
  }

  .week-range-text {
    font-size: 1.45rem;
    font-weight: 700;
    color: var(--text-main);
    letter-spacing: -0.01em;
  }

  .controls-container {
    display: flex;
    align-items: center;
    gap: 1.25rem;
  }

  .nav-group {
    display: flex;
    align-items: center;
    background-color: var(--bg-surface-alt);
    padding: 4px;
    border-radius: var(--radius-md);
    border: 1px solid var(--border-subtle);
  }

  .touch-btn {
    min-height: var(--min-touch-target);
    min-width: var(--min-touch-target);
    padding: 0 1rem;
    border-radius: var(--radius-sm);
    font-weight: 600;
    font-size: 1rem;
    color: var(--text-main);
    transition: background-color 0.15s ease, transform 0.1s ease;
  }

  .nav-arrow {
    padding: 0 0.85rem;
    color: var(--accent-walnut);
  }

  .nav-arrow:active, .today-btn:active {
    background-color: var(--border-strong);
  }

  .today-btn {
    padding: 0 1.2rem;
    font-size: 0.95rem;
    border-left: 1px solid var(--border-subtle);
    border-right: 1px solid var(--border-subtle);
    border-radius: 0;
  }

  .add-event-btn {
    background-color: var(--accent-walnut);
    color: #FFFFFF;
    padding: 0 1.4rem;
    border-radius: var(--radius-md);
    gap: 0.5rem;
    font-size: 1.05rem;
    font-weight: 600;
    box-shadow: 0 2px 8px rgba(74, 58, 49, 0.2);
  }

  .add-event-btn:active {
    background-color: var(--accent-walnut-hover);
  }

  .plus-icon {
    font-size: 1.4rem;
    line-height: 1;
    font-weight: 400;
  }

  @media (max-width: 1366px) {
    .nav-bar {
      padding: 1rem 1.25rem;
    }
    .week-range-text {
      font-size: 1.25rem;
    }
  }
</style>

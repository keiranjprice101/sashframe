<script lang="ts">
  import { addDays, formatWeekRange } from '../lib/dates';

  interface Props {
    currentWeekStart: Date;
    onPrevWeek: () => void;
    onNextWeek: () => void;
    onToday: () => void;
    onAddEvent: () => void;
  }

  let { 
    currentWeekStart, 
    onPrevWeek, 
    onNextWeek, 
    onToday, 
    onAddEvent
  }: Props = $props();

  let weekEnd = $derived(addDays(currentWeekStart, 6));
  let formattedRange = $derived(formatWeekRange(currentWeekStart, weekEnd));
</script>

<header class="calendar-header">
  <div class="masthead-row">
    <h2 class="week-heading">{formattedRange}</h2>

    <div class="masthead-controls">
      <nav class="nav-cluster" aria-label="Week navigation">
        <button 
          type="button" 
          class="masthead-btn nav-arrow" 
          onclick={onPrevWeek} 
          aria-label="Previous week"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="15 18 9 12 15 6"></polyline>
          </svg>
        </button>

        <button 
          type="button" 
          class="masthead-btn today-btn" 
          onclick={onToday}
        >
          Today
        </button>

        <button 
          type="button" 
          class="masthead-btn nav-arrow" 
          onclick={onNextWeek} 
          aria-label="Next week"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="9 18 15 12 9 6"></polyline>
          </svg>
        </button>
      </nav>

      <span class="control-divider" aria-hidden="true"></span>

      <button 
        type="button" 
        class="masthead-btn add-btn" 
        onclick={onAddEvent}
        aria-label="Add event"
        title="Add event"
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <line x1="12" y1="5" x2="12" y2="19"></line>
          <line x1="5" y1="12" x2="19" y2="12"></line>
        </svg>
      </button>
    </div>
  </div>
</header>

<style>
  .calendar-header {
    display: flex;
    flex-direction: column;
    padding: 1.5rem 1.75rem 1.25rem 1.75rem;
    background-color: var(--bg-surface);
    border-bottom: 1px solid var(--border-hairline);
    flex-shrink: 0;
  }

  .masthead-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1.5rem;
  }

  .week-heading {
    font-size: 1.65rem;
    font-weight: 500;
    color: var(--text-main);
    letter-spacing: -0.02em;
    line-height: 1.2;
    margin: 0;
  }

  .masthead-controls {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .nav-cluster {
    display: inline-flex;
    align-items: center;
    gap: 0.2rem;
  }

  .masthead-btn {
    min-height: 44px;
    min-width: 44px;
    padding: 0 0.5rem;
    border-radius: var(--radius-sm);
    color: var(--text-muted);
    background: transparent;
    border: none;
    cursor: pointer;
    transition: color 0.15s ease, background-color 0.15s ease, transform 0.1s ease;
  }

  .masthead-btn:hover {
    color: var(--text-main);
    background-color: var(--control-hover);
  }

  .masthead-btn:focus-visible {
    outline: 2px solid var(--accent-walnut);
    outline-offset: 2px;
  }

  .masthead-btn:active {
    background-color: var(--control-hover);
    color: var(--text-main);
    transform: scale(0.96);
  }

  .today-btn {
    padding: 0 0.85rem;
    font-size: 0.95rem;
    font-weight: 500;
    color: var(--text-muted);
    letter-spacing: 0.01em;
  }

  .control-divider {
    width: 1px;
    height: 18px;
    background-color: var(--border-hairline);
    opacity: 0.75;
  }

  .add-btn {
    color: var(--text-muted);
  }

  @media (max-width: 1366px) {
    .calendar-header {
      padding: 1.15rem 1.25rem 1rem 1.25rem;
    }
    .week-heading {
      font-size: 1.4rem;
    }
  }
</style>

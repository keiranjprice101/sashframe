<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import type { Photo, Weather } from '../lib/types';
  import { formatDisplayDate, formatDayName, formatLiveTime } from '../lib/dates';

  interface Props {
    photos?: Photo[];
    weather?: Weather;
    rotationIntervalMs?: number;
  }

  let { 
    photos = [], 
    weather = { temperature: 14, unit: '°C', condition: 'Cloudy' }, 
    rotationIntervalMs = 60000 
  }: Props = $props();

  let currentIndex = $state(0);
  let now = $state(new Date());

  let timer: ReturnType<typeof setInterval>;
  let clockTimer: ReturnType<typeof setInterval>;

  function nextPhoto() {
    if (photos.length === 0) return;
    currentIndex = (currentIndex + 1) % photos.length;
  }

  onMount(() => {
    // 60-second photo rotation timer
    timer = setInterval(() => {
      nextPhoto();
    }, rotationIntervalMs);

    // 1-second live clock timer
    clockTimer = setInterval(() => {
      now = new Date();
    }, 1000);
  });

  onDestroy(() => {
    if (timer) clearInterval(timer);
    if (clockTimer) clearInterval(clockTimer);
  });
</script>

<!-- Photo Panel container (approx 40% width in kiosk layout) -->
<div 
  class="photo-panel" 
  onclick={nextPhoto}
  role="button"
  tabindex="0"
  aria-label="Tap to show next photo"
>
  <!-- Render all photos stacked for crossfade transition -->
  {#each photos as photo, idx (photo.id)}
    <div 
      class="photo-slide"
      class:active={idx === currentIndex}
      style="background-image: url('{photo.url}');"
    ></div>
  {/each}

  <!-- Dark gradient scrim for legibility -->
  <div class="gradient-scrim"></div>
  <div class="radial-scrim"></div>

  <!-- Integrated typographic overlay directly on image -->
  <div class="overlay-content">
    <div class="top-meta">
      <div class="weather-display">
        <span class="weather-icon" aria-hidden="true">
          {#if weather.condition.toLowerCase().includes('cloud')}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
            </svg>
          {:else if weather.condition.toLowerCase().includes('rain')}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
              <path d="M16 14v6" />
              <path d="M8 14v6" />
              <path d="M12 16v6" />
            </svg>
          {:else if weather.condition.toLowerCase().includes('clear') || weather.condition.toLowerCase().includes('sun')}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="4" />
              <path d="M12 2v2" />
              <path d="M12 20v2" />
              <path d="m4.93 4.93 1.41 1.41" />
              <path d="m17.66 17.66 1.41 1.41" />
              <path d="M2 12h2" />
              <path d="M20 12h2" />
              <path d="m6.34 17.66-1.41 1.41" />
              <path d="m19.07 4.93-1.41 1.41" />
            </svg>
          {:else}
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
            </svg>
          {/if}
        </span>
        <span class="weather-temp">{weather.temperature}{weather.unit}</span>
        <span class="weather-dot">·</span>
        <span class="weather-cond">{weather.condition}</span>
      </div>
    </div>

    <div class="bottom-time-date">
      <div class="time-display">{formatLiveTime(now)}</div>
      <div class="date-group">
        <div class="day-name">{formatDayName(now)}</div>
        <div class="full-date">{formatDisplayDate(now)}</div>
      </div>
    </div>
  </div>
</div>

<style>
  .photo-panel {
    position: relative;
    width: 40%;
    height: 100%;
    flex-shrink: 0;
    overflow: hidden;
    cursor: pointer;
    background-color: #1a1614;
  }

  .photo-slide {
    position: absolute;
    inset: 0;
    background-size: cover;
    background-position: center;
    background-repeat: no-repeat;
    opacity: 0;
    transition: opacity 1.2s cubic-bezier(0.4, 0, 0.2, 1);
    will-change: opacity;
  }

  .photo-slide.active {
    opacity: 1;
    z-index: 1;
  }

  .gradient-scrim {
    position: absolute;
    inset: 0;
    z-index: 2;
    pointer-events: none;
    background: linear-gradient(
      to bottom,
      rgba(0, 0, 0, 0.42) 0%,
      rgba(0, 0, 0, 0.15) 15%,
      transparent 30%,
      transparent 45%,
      rgba(0, 0, 0, 0.45) 75%,
      rgba(0, 0, 0, 0.78) 100%
    );
  }

  .radial-scrim {
    position: absolute;
    inset: 0;
    z-index: 2;
    pointer-events: none;
    background: radial-gradient(
      ellipse 85% 65% at 0% 100%,
      rgba(12, 10, 8, 0.65) 0%,
      rgba(12, 10, 8, 0.32) 45%,
      transparent 75%
    );
  }

  .overlay-content {
    position: absolute;
    inset: 0;
    z-index: 3;
    pointer-events: none;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    padding: 2.75rem 3rem;
    color: #ffffff;
  }

  .weather-display {
    display: inline-flex;
    align-items: center;
    gap: 0.55rem;
    font-size: 1.1rem;
    font-weight: 450;
    letter-spacing: 0.02em;
    color: rgba(255, 255, 255, 0.95);
    text-shadow: 0 1px 3px rgba(0, 0, 0, 0.65), 0 3px 12px rgba(0, 0, 0, 0.45);
  }

  .weather-icon {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .weather-temp {
    font-weight: 550;
  }

  .weather-dot {
    opacity: 0.5;
  }

  .weather-cond {
    font-weight: 350;
    opacity: 0.9;
  }

  .bottom-time-date {
    display: flex;
    flex-direction: column;
    text-shadow: 0 1px 3px rgba(0, 0, 0, 0.65), 0 4px 16px rgba(0, 0, 0, 0.5);
  }

  .time-display {
    font-size: 4.75rem;
    font-weight: 350;
    line-height: 0.92;
    letter-spacing: -0.035em;
    font-variant-numeric: normal;
    color: #FFFFFF;
  }

  .date-group {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    margin-top: 0.85rem;
  }

  .day-name {
    font-size: 1.95rem;
    font-weight: 500;
    line-height: 1.2;
    letter-spacing: -0.01em;
    color: #FAF8F5;
  }

  .full-date {
    font-size: 1.2rem;
    font-weight: 350;
    opacity: 0.88;
    letter-spacing: 0.01em;
    color: #FFFFFF;
  }

  @media (max-width: 1366px) {
    .photo-panel {
      width: 38%;
    }
    .overlay-content {
      padding: 2rem 2.25rem;
    }
    .time-display {
      font-size: 3.6rem;
    }
    .day-name {
      font-size: 1.6rem;
    }
    .full-date {
      font-size: 1.05rem;
    }
  }
</style>

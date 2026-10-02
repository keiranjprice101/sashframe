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

  <!-- Unobtrusive elegant overlay -->
  <div class="overlay-content">
    <div class="top-meta">
      <div class="weather-badge">
        <span class="weather-icon">☁️</span>
        <span class="weather-temp">{weather.temperature}{weather.unit}</span>
        <span class="weather-dot">·</span>
        <span class="weather-cond">{weather.condition}</span>
      </div>
    </div>

    <div class="bottom-time-date">
      <div class="time-display">{formatLiveTime(now)}</div>
      <div class="day-name">{formatDayName(now)}</div>
      <div class="full-date">{formatDisplayDate(now)}</div>
      
      {#if photos[currentIndex]}
        <div class="photo-caption">
          📍 {photos[currentIndex].caption} {photos[currentIndex].location ? `— ${photos[currentIndex].location}` : ''}
        </div>
      {/if}
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
      rgba(0, 0, 0, 0.4) 0%,
      transparent 30%,
      transparent 50%,
      rgba(0, 0, 0, 0.75) 100%
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
    padding: 2.25rem 2.5rem;
    color: #ffffff;
    text-shadow: 0 2px 8px rgba(0, 0, 0, 0.6);
  }

  .weather-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 1.15rem;
    font-weight: 500;
    letter-spacing: 0.02em;
    color: rgba(255, 255, 255, 0.95);
    background: rgba(0, 0, 0, 0.25);
    backdrop-filter: blur(8px);
    padding: 0.5rem 1.1rem;
    border-radius: var(--radius-full);
    border: 1px solid rgba(255, 255, 255, 0.15);
  }

  .weather-icon {
    font-size: 1.25rem;
  }

  .weather-dot {
    opacity: 0.6;
  }

  .bottom-time-date {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .time-display {
    font-size: 3.75rem;
    font-weight: 700;
    line-height: 1;
    letter-spacing: -0.03em;
    font-variant-numeric: tabular-nums;
  }

  .day-name {
    font-size: 2.2rem;
    font-weight: 600;
    line-height: 1.15;
    margin-top: 0.4rem;
    letter-spacing: -0.01em;
    color: #F8F6F0;
  }

  .full-date {
    font-size: 1.25rem;
    font-weight: 400;
    opacity: 0.9;
    letter-spacing: 0.01em;
  }

  .photo-caption {
    margin-top: 1rem;
    font-size: 0.9rem;
    font-style: italic;
    opacity: 0.75;
  }

  @media (max-width: 1366px) {
    .photo-panel {
      width: 38%;
    }
    .time-display {
      font-size: 3.2rem;
    }
    .day-name {
      font-size: 1.8rem;
    }
    .full-date {
      font-size: 1.1rem;
    }
  }
</style>

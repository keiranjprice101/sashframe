<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import type { Photo, PhotoManifestItem, Weather } from '../lib/types';
  import { formatDisplayDate, formatDayName, formatLiveTime } from '../lib/dates';
  import { fetchLocalWeather } from '../lib/weather';
  import { ShuffleBag } from '../lib/shuffle';

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

  let manifestPhotos = $state<Photo[]>([]);
  let manifestLoaded = $state(false);
  let activePhotos = $derived(manifestLoaded ? manifestPhotos : photos);
  let currentWeather = $state<Weather>(weather);

  let currentPhoto = $state<Photo | undefined>(undefined);
  let previousPhoto = $state<Photo | undefined>(undefined);
  let currentPhotoReady = $state(false);
  let currentPhotoId = $derived(currentPhoto?.id);
  let renderedPhotos = $derived(
    previousPhoto ? [previousPhoto, ...(currentPhoto ? [currentPhoto] : [])] : currentPhoto ? [currentPhoto] : []
  );
  let now = $state(new Date());

  const photoBag = new ShuffleBag<Photo>([], {
    getId: (p) => p.id,
  });

  let timer: ReturnType<typeof setInterval>;
  let clockTimer: ReturnType<typeof setInterval>;
  let weatherTimer: ReturnType<typeof setInterval>;
  let manifestTimer: ReturnType<typeof setInterval>;
  let manifestRequest: AbortController | undefined;
  let manifestEtag: string | undefined;
  let fadeTimer: ReturnType<typeof setTimeout> | undefined;

  function selectPhoto(photo: Photo | undefined) {
    if (photo?.id === currentPhoto?.id) return;
    if (fadeTimer) clearTimeout(fadeTimer);
    // Keep only the outgoing and incoming image, regardless of library size.
    previousPhoto = photo ? (currentPhotoReady ? currentPhoto : previousPhoto) : undefined;
    if (previousPhoto?.id === photo?.id) previousPhoto = undefined;
    currentPhotoReady = false;
    currentPhoto = photo;
  }

  function photoLoaded(id: string) {
    if (id !== currentPhoto?.id || currentPhotoReady) return;
    currentPhotoReady = true;
    fadeTimer = setTimeout(() => { previousPhoto = undefined; }, 1250);
  }

  function updateBagAndSelect(items: Photo[]) {
    photoBag.setItems(items);
    const first = photoBag.next();
    selectPhoto(first);
  }

  function advancePhoto() {
    if (activePhotos.length <= 1) {
      selectPhoto(activePhotos[0]);
      return;
    }
    const next = photoBag.next();
    if (next) {
      selectPhoto(next);
    }
  }

  async function refreshPhotoManifest() {
    if (manifestRequest) return;
    const controller = new AbortController();
    manifestRequest = controller;
    try {
      const res = await fetch('/api/photos', {
        headers: manifestEtag ? { 'If-None-Match': manifestEtag } : {},
        cache: 'no-cache',
        signal: controller.signal,
      });
      if (res.status === 304) return;
      if (!res.ok) return;
      const data: PhotoManifestItem[] = await res.json();
      if (controller.signal.aborted || !Array.isArray(data)) return;
      manifestEtag = res.headers.get('ETag') ?? undefined;
      const nextPhotos = data.map(item => ({
          id: item.id,
          url: item.src,
          caption: item.sourceName,
          sourceName: item.sourceName,
          width: item.width,
          height: item.height
      }));
      if (!manifestLoaded || JSON.stringify(nextPhotos) !== JSON.stringify(manifestPhotos)) {
        manifestPhotos = nextPhotos;
        manifestLoaded = true;
        photoBag.setItems(nextPhotos);
        // Preserve the displayed photo when it still exists; refreshes aren't rotations.
        if (!nextPhotos.some(photo => photo.id === currentPhotoId)) {
          selectPhoto(photoBag.next());
        }
      }
    } catch {
      // Keep the current slideshow on transient network failures.
    } finally {
      manifestRequest = undefined;
    }
  }

  onMount(() => {
    // Initialize bag with props.photos if present before manifest fetch
    if (photos.length > 0) {
      updateBagAndSelect(photos);
    }

    refreshPhotoManifest();
    manifestTimer = setInterval(refreshPhotoManifest, 30000);

    // Photo rotation timer (~60 seconds default)
    timer = setInterval(() => {
      advancePhoto();
    }, rotationIntervalMs);

    // 1-second live clock timer
    clockTimer = setInterval(() => {
      now = new Date();
    }, 1000);

    async function updateWeather() {
      try {
        const fresh = await fetchLocalWeather();
        currentWeather = fresh;
      } catch {
        // Fallback to default or previous weather on network failure
      }
    }

    // Fetch live weather immediately on mount
    updateWeather();

    // Refresh weather every 10 minutes
    weatherTimer = setInterval(updateWeather, 10 * 60 * 1000);
  });

  onDestroy(() => {
    if (timer) clearInterval(timer);
    if (clockTimer) clearInterval(clockTimer);
    if (weatherTimer) clearInterval(weatherTimer);
    if (manifestTimer) clearInterval(manifestTimer);
    manifestRequest?.abort();
    if (fadeTimer) clearTimeout(fadeTimer);
  });
</script>

<!-- Photo Panel container (47% width in kiosk layout) -->
<div class="photo-panel">
  <!-- Mount at most two images; release the outgoing one after its crossfade. -->
  {#each renderedPhotos as photo (photo.id)}
    <img
      class="photo-slide"
      class:active={photo.id === currentPhotoId && currentPhotoReady}
      class:outgoing={photo.id === previousPhoto?.id}
      class:waiting={photo.id === previousPhoto?.id && !currentPhotoReady}
      src={photo.url}
      alt=""
      decoding="async"
      onload={() => photoLoaded(photo.id)}
    />
  {/each}

  <!-- Dark gradient scrim for legibility -->
  <div class="gradient-scrim"></div>
  <div class="radial-scrim"></div>

  <!-- Integrated typographic overlay directly on image -->
  <div class="overlay-content">
    <div class="top-meta">
      <div class="weather-display">
        <span class="weather-icon" aria-hidden="true">
          {#if currentWeather.condition.toLowerCase().includes('cloud') || currentWeather.condition.toLowerCase().includes('overcast')}
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
            </svg>
          {:else if currentWeather.condition.toLowerCase().includes('rain') || currentWeather.condition.toLowerCase().includes('drizzle') || currentWeather.condition.toLowerCase().includes('shower')}
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" />
              <path d="M16 14v6" />
              <path d="M8 14v6" />
              <path d="M12 16v6" />
            </svg>
          {:else if currentWeather.condition.toLowerCase().includes('snow')}
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M20 17.58A5 5 0 0 0 18 8h-1.26A8 8 0 1 0 4 16.25" />
              <line x1="8" y1="16" x2="8.01" y2="16" />
              <line x1="8" y1="20" x2="8.01" y2="20" />
              <line x1="12" y1="18" x2="12.01" y2="18" />
              <line x1="12" y1="22" x2="12.01" y2="22" />
              <line x1="16" y1="16" x2="16.01" y2="16" />
              <line x1="16" y1="20" x2="16.01" y2="20" />
            </svg>
          {:else if currentWeather.condition.toLowerCase().includes('thunder')}
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M19 16.9A5 5 0 0 0 18 7h-1.26a8 8 0 1 0-11.62 9" />
              <polyline points="13 11 9 17 15 17 11 23" />
            </svg>
          {:else if currentWeather.condition.toLowerCase().includes('fog')}
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <line x1="4" y1="14" x2="20" y2="14" />
              <line x1="4" y1="18" x2="20" y2="18" />
              <path d="M17.5 10H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
            </svg>
          {:else if currentWeather.condition.toLowerCase().includes('clear') || currentWeather.condition.toLowerCase().includes('sun')}
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
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
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" />
            </svg>
          {/if}
        </span>
        <span class="weather-temp">{currentWeather.temperature}{currentWeather.unit}</span>
        <span class="weather-dot">·</span>
        <span class="weather-cond">{currentWeather.condition}</span>
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
    width: 47%;
    height: 100%;
    flex-shrink: 0;
    overflow: hidden;
    background-color: #1a1614;
  }

  .photo-slide {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    object-position: center;
    opacity: 0;
    transition: opacity 1.2s cubic-bezier(0.4, 0, 0.2, 1);
  }

  .photo-slide.active {
    opacity: 1;
    z-index: 1;
  }

  .photo-slide.outgoing {
    z-index: 2;
  }

  .photo-slide.waiting {
    opacity: 1;
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
    gap: 0.75rem;
    font-size: 1.45rem;
    font-weight: 450;
    letter-spacing: 0.01em;
    color: rgba(255, 255, 255, 0.96);
    text-shadow: 0 1px 4px rgba(0, 0, 0, 0.7), 0 3px 14px rgba(0, 0, 0, 0.5);
  }

  .weather-icon {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .weather-icon svg {
    width: 1.65rem;
    height: 1.65rem;
  }

  .weather-temp {
    font-weight: 550;
  }

  .weather-dot {
    opacity: 0.5;
    margin: 0 0.1rem;
  }

  .weather-cond {
    font-weight: 380;
    opacity: 0.92;
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
      width: 45%;
    }
    .overlay-content {
      padding: 2rem 2.25rem;
    }
    .weather-display {
      font-size: 1.25rem;
      gap: 0.6rem;
    }
    .weather-icon svg {
      width: 1.4rem;
      height: 1.4rem;
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

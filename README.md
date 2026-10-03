# Sashframe

A custom household calendar display designed to run fullscreen on a **15.6-inch 1920×1080 touchscreen** in Chromium kiosk mode on a Raspberry Pi.

It features a horizontal layout inspired by a traditional photo calendar, with a warm, minimal, editorial design aesthetic suited for a walnut physical frame mounted on a wall or placed on a kitchen counter.

> **Design Philosophy**: *"Typeset schedule, not productivity dashboard."*  
> Inspired by Apple, Kindle, Muji, and high-end editorial print design—prioritizing typography, generous whitespace, and domestic calm over SaaS cards, badges, and heavy borders.

---

## 📐 Layout & Feature Overview

### 📷 Photo Panel (Left ~40%)
- **Full-Bleed Photography**: Auto-rotating local slideshow (60s default interval) with smooth crossfade transitions.
- **Integrated Readability Scrims**: Dual subtle dark linear gradient and radial vignette over the photo for legibility on bright backgrounds without visually boxed glass cards.
- **Typographic Clock & Weather Overlay**:
  - Direct-on-image 24-hour live clock with London BST awareness.
  - Clean day of week and full date display (non-redundant).
  - Minimal weather indicator with lightweight icon (`14°C · Cloudy`).
- **Touch-Friendly**: Tap anywhere on the photo panel to advance to the next picture immediately.

### 📅 Calendar Panel (Right ~60%)
- **Editorial Masthead**:
  - Clean date range heading (e.g. `September 28 – October 4`).
  - Minimalist week navigation (`‹`, `Today`, `›`) and lightweight `+` add event action.
- **Whitespace-Driven 7-Day Grid**:
  - Monday-to-Sunday columns separated by hairline dividers and generous whitespace.
  - Unboxed day numbers with a soft circular indicator for the current day.
  - All-day events row at the top of each day column.
  - Chronological timed schedule entries.
- **Schedule Entries (Non-Card Treatment)**:
  - Clean typographic schedule entries instead of rounded SaaS/Kanban cards or heavy shadows.
  - Event title as primary visual element, time secondary, and location tertiary.
  - Thin 2px vertical accent bar color-coded by household member (**Alex** in terracotta coral, **Sham** in muted sage emerald).
- **Interactive Modals**:
  - Touch-accessible event detail dialog (View / Edit / Delete).
  - Add-event dialog with member selection, title, date, time, location, and notes.

### 🌓 Solar-Driven Automatic Day/Night Theme
- **Zero-API Local Schedule**: Automatically switches between Light and Dark mode using a built-in 2-value-per-day astronomical lookup table (`[sunrise, sunset]`) calibrated for **UK South East England** (~51.3° N, 0.0° W).
- **Light Mode After Sunrise, Dark Mode After Sunset**: Matches natural circadian rhythms without requiring an internet connection or external weather/astronomy API in production.
- **BST / GMT Civil Time Aware**: Seamlessly accounts for British Summer Time (UTC+1) and Greenwich Mean Time (UTC+0).
- **Real-Time Kiosk Transition**: Checks every 30 seconds while the display is running, smoothly transitioning when sunrise or sunset occurs.
- **Instant Pre-Render**: Injected synchronously in `<head>` before the DOM paints to prevent theme flashing on load or reboots.
- **Warm Charcoal Palette**: Dark mode utilizes deep warm charcoal tones (`#181412` base, `#1E1A17` surface) and soft off-white typography (`#EAE4DC`), complementing a physical walnut display frame.

---

## 🛠️ Tech Stack & Constraints

- **Framework**: [Astro 5](https://astro.build) + [Svelte 5](https://svelte.dev) (runes-based reactive components)
- **Language**: TypeScript
- **Styling**: Scoped CSS with centralized CSS custom property tokens (`:root` and `html[data-theme="dark"]` in [`src/styles/global.css`](file:///home/sham/sashframe/src/styles/global.css))
- **Typography**: System font stack (`system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto`)
- **Touch Accessibility**: Touch targets ≥ 44px with subtle active/hover states and native touch manipulation resets.
- **Zero Heavy Dependencies**: Pure Astro and Svelte with zero runtime component libraries or heavy icon packs.

---

## 📁 Architecture & File Structure

```text
public/
  photos/                  # Fallback/placeholder photography assets
data/
  photos/
    incoming/              # Drop incoming images here (.jpg, .jpeg, .png, .webp)
    processed/             # Ingested, resized WebP images (<hash>.webp)
    manifest.json          # Generated manifest consumed by /api/photos
scripts/
  install.sh               # One-step environment setup (creates .venv, installs Python & Node packages)
  dev.sh                   # Process supervisor starting Astro and photo watcher
services/
  photos/
    processor.py           # Watchdog filesystem event monitor and debounced runner
    processing.py          # Validation, EXIF transpose, aspect-ratio resize, WebP conversion
    manifest.py            # Manifest generation, reconciliation, and orphan cleanup
src/
  components/
    PhotoPanel.svelte      # Rotating photo slide with manifest polling & clock overlay
    DateNavigation.svelte  # Week navigation masthead & add event trigger
    CalendarWeek.svelte    # 7-day week schedule grid with editorial entries
    EventModal.svelte      # Event details popup (View / Edit / Delete)
    AddEventModal.svelte   # Modal form for creating new events
    DashboardApp.svelte    # Root Svelte container, theme state, & session state
  data/
    mock.ts                # Seed household members, events, weather, & photos
  lib/
    types.ts               # TypeScript interfaces (CalendarEvent, PhotoManifestItem, etc.)
    dates.ts               # Date math, ISO formatters, BST-aware 24h clock utilities
    sunSchedule.ts         # 366-day UK South East sunrise/sunset schedule & solar theme evaluators
  pages/
    api/
      photos.ts            # Dynamic API endpoint serving data/photos/manifest.json
    photos/
      [...image].ts        # File route serving processed WebP images
    index.astro            # Fullscreen Kiosk page shell with theme pre-init script
  styles/
    global.css             # Light/dark design tokens, typography, & touch resets
```

---

## 🚀 Running & Development

### 1. One-Step Environment Setup
Run the unified setup script to automatically create `.venv`, install Python dependencies (`Pillow`, `watchdog`), and install npm dependencies:
```bash
npm run setup
# or: bash scripts/install.sh
```

*(Alternatively, manual setup: `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt && npm install`)*

### 3. Start Development Environment
Run a single command from the project root:
```bash
npm run dev
```

This starts:
- **Astro dev server** (with hot-reload and dynamic `/api/photos` endpoint)
- **Python photo watcher** (monitoring `data/photos/incoming/` with completed-write semantics)

Pressing `Ctrl+C` cleanly terminates both processes without leaving orphaned Python or Node workers.

#### Component-specific dev commands:
- `npm run dev:astro` — Astro dev server only
- `npm run dev:photos` — Python photo processor only

### 4. Testing the Photo Ingestion Pipeline
1. While `npm run dev` is running, copy any `.jpg`, `.jpeg`, `.png`, or `.webp` file into `data/photos/incoming/`:
   ```bash
   cp ~/Pictures/sample.jpg data/photos/incoming/
   ```
2. The watcher detects write completion, validates the image, normalizes EXIF orientation, scales to max 1920px (preserving aspect ratio without upscaling), converts to WebP, and writes atomically to `data/photos/processed/<hash>.webp`.
3. The manifest is regenerated at `data/photos/manifest.json`.
4. The Astro frontend polls `/api/photos` every 5 seconds, picks up the new image, and adds it to the photo rotation without reloading the page or restarting the server.
5. Deleting the file from `data/photos/incoming/` automatically removes it from `manifest.json` and deletes the orphaned `.webp` file.

### 5. Production Build & Type Checking
```bash
# Run production build
npm run build

# Run TypeScript type check across Astro and Svelte files
npx astro check
```

---

## 📋 TODO & Roadmap

### 🔄 Photo Pipeline & Integrations
- [ ] **Google Drive / rclone Sync**: Upstream sync step to periodically mirror a shared Google Drive album into `data/photos/incoming/`.
- [ ] **HEIC / HEIF Format Support**: Add `pillow-heif` support once system libraries (`libheif`) are available.
- [ ] **Local Photo Reader**: Integration with Immich or local network folder (Syncthing/SMB).

### 📅 Calendar & Weather
- [ ] **Calendar Synchronization**: Connect to CalDAV / iCal feeds, Google Calendar, or Apple iCloud API.
- [ ] **Live Weather Feed**: Replace mock weather with a live API (e.g., Open-Meteo or local Weather Underground station).

### 💾 Storage & Backend
- [ ] **Persistence Layer**: Store created/edited events in SQLite or a lightweight local JSON store.
- [ ] **Remote Editing**: Web/mobile portal to allow household members to add events remotely.

### 🖥️ Hardware & Kiosk
- [ ] **Raspberry Pi Configuration**: Chromium kiosk autostart script (`--kiosk --incognito`) & systemd service.
- [ ] **Display Power Management**: Ambient light sensing or bedtime screen dimming schedule to preserve display lifespan.

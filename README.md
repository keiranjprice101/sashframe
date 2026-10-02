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
  - Top-right icon-only theme toggle.
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

### 🌓 Dark Mode
- **Warm Charcoal Aesthetic**: Designed for dark display glass, walnut framing, and evening domestic lighting. Uses very dark warm charcoal tones (`#181412` base, `#1E1A17` surface, `#26211D` elevated) rather than harsh OLED black or cold developer blue-slate.
- **Soft Typographic Contrast**: Soft off-white text (`#EAE4DC`), muted secondary text, warm walnut amber today badge, and subtly lifted household accents for readable contrast.
- **Unaltered Photography**: Photographs remain full-bleed and unaltered in both light and dark modes.
- **Zero-Flicker Persistence**: Selected theme is stored in `localStorage` (`'sashframe-theme'`) and pre-applied via a synchronous `<head>` script to eliminate theme flashing during reloads or device reboots.

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
  photos/                  # Local photography assets
src/
  components/
    PhotoPanel.svelte      # Rotating photo slide with weather, 24h clock, & scrims
    DateNavigation.svelte  # Week navigation masthead, add event trigger, & dark mode toggle
    CalendarWeek.svelte    # 7-day week schedule grid with editorial entries
    EventModal.svelte      # Event details popup (View / Edit / Delete)
    AddEventModal.svelte   # Modal form for creating new events
    DashboardApp.svelte    # Root Svelte container, theme state, & session state
  data/
    mock.ts                # Seed household members, events, weather, & photos
  lib/
    types.ts               # TypeScript interfaces (CalendarEvent, Member, Weather, etc.)
    dates.ts               # Date math, ISO formatters, BST-aware 24h clock utilities
  pages/
    index.astro            # Fullscreen Kiosk page shell with theme pre-init script
  styles/
    global.css             # Light/dark design tokens, typography, & touch resets
```

---

## 🚀 Running & Building

```bash
# Start background development server (per project rule)
astro dev --background

# Check dev server status, logs, or stop
astro dev status
astro dev logs
astro dev stop

# Run production build
npm run build

# Run TypeScript type check across Astro and Svelte files
npx astro check
```

---

## 📋 TODO & Roadmap

### 🔄 Data & Integrations
- [ ] **Calendar Synchronization**: Connect to CalDAV / iCal feeds, Google Calendar, or Apple iCloud API.
- [ ] **Live Weather Feed**: Replace mock weather with a live API (e.g., Open-Meteo or local Weather Underground station).
- [ ] **Photo Source Integration**: Dynamic image loading from a local folder, Immich, or Syncthing share.

### 💾 Storage & Backend
- [ ] **Persistence Layer**: Store created/edited events in SQLite or a lightweight local JSON store.
- [ ] **Remote Editing**: Web/mobile portal to allow household members to add events remotely.

### 🖥️ Hardware & Kiosk
- [ ] **Raspberry Pi Configuration**: Chromium kiosk autostart script (`--kiosk --incognito`) & systemd service.
- [ ] **Display Power Management**: Ambient light sensing or bedtime screen dimming schedule to preserve display lifespan.

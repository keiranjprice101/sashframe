# Sashframe

A custom household calendar display designed to run fullscreen on a **15.6-inch 1920×1080 touchscreen** in Chromium kiosk mode on a Raspberry Pi.

It features a modern horizontal layout inspired by a traditional photo calendar, with a warm, minimal design aesthetic suited for a walnut physical frame mounted on a wall or placed on a kitchen counter.

---

## 📐 Layout Overview

- **Photo Panel (Left ~40%)**:
  - Auto-rotating local slideshow (60s default interval).
  - Tap/click photo to advance immediately to the next photo.
  - Smooth opacity crossfade transitions.
  - Unobtrusive corner overlay displaying live time, day of the week, full date, and weather info (`14°C · Cloudy`).
  - Subtle dark gradient scrim for text legibility.

- **Calendar Panel (Right ~60%)**:
  - Horizontal 7-day week view (Monday through Sunday).
  - All-day events row at the top of each day column.
  - Timed events list displayed chronologically.
  - Household member color-coding (**Alex** in warm terracotta coral, **Sham** in muted sage emerald).
  - Touch-friendly navigation controls (`Prev`, `Today`, `Next`) and prominent `+ Add Event` trigger.
  - Touch-friendly event detail modal with placeholder Edit/Delete options.
  - Event creation modal supporting in-memory updates for the current session.

---

## 🛠️ Tech Stack & Constraints

- **Framework**: [Astro 5](https://astro.build) + [Svelte 5](https://svelte.dev) (for interactive components)
- **Language**: TypeScript
- **Styling**: Scoped CSS with custom CSS design tokens ([`src/styles/global.css`](file:///home/sham/sashframe/src/styles/global.css))
- **Typography**: System font stack (`system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto`)
- **Touch**: Large touch targets (minimum 48px height) with no reliance on hover states.
- **Dependencies**: Zero heavy UI component libraries or runtime CDN fonts.

---

## 📁 Architecture & File Structure

```text
public/
  photos/                  # Local placeholder photography
src/
  components/
    PhotoPanel.svelte      # Rotating photo panel with weather & clock overlay
    DateNavigation.svelte  # Week navigation bar & Add Event button
    CalendarWeek.svelte    # 7-day week grid & event cards
    EventModal.svelte      # Event details popup (View / Edit / Delete)
    AddEventModal.svelte   # Form modal for creating new events
    DashboardApp.svelte    # Root Svelte container & session state management
  data/
    mock.ts                # Mock household members, events, weather, & photos
  lib/
    types.ts               # TypeScript interfaces (CalendarEvent, Member, etc.)
    dates.ts               # Date math, ISO formatting, & 12h clock utilities
  pages/
    index.astro            # Fullscreen Kiosk page shell
  styles/
    global.css             # Design tokens, color palette, & touch resets
```

---

## 🚀 Running & Building

```bash
# Start development server
npm run dev

# Run production build
npm run build

# Run TypeScript type check across Astro and Svelte files
npx astro check
```

---

## 📋 TODO & Roadmap

### 🔄 Data & Integrations
- [ ] **Real Calendar Integration**: Connect to iCal / CalDAV, Google Calendar, or Apple iCloud API feeds.
- [ ] **Live Weather Feed**: Replace mock weather with an API integration (e.g. Open-Meteo or local home weather station).
- [ ] **Local Photo Reader**: Automatic scanning of a local directory or Immich / Syncthing sync folder.

### 💾 Storage & Backend
- [ ] **Persistence Layer**: Store added/modified events in a local SQLite database or JSON backend.
- [ ] **Multi-User Sync**: Support updating events from mobile or web browser.

### 🖥️ Hardware & Kiosk
- [ ] **Raspberry Pi Setup**: Chromium kiosk autostart script & systemd service config.
- [ ] **Display Power Management**: Motion sensor / screen dimming schedule to conserve display panel life.

import type { APIRoute } from 'astro';
import { loadShifterEvents } from '../../lib/shifter';

export const GET: APIRoute = async () => {
  try {
    const events = loadShifterEvents();
    return new Response(JSON.stringify(events), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store, no-cache, must-revalidate'
      }
    });
  } catch {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store, no-cache, must-revalidate'
      }
    });
  }
};

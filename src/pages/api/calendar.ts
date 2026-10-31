import type { APIRoute } from 'astro';
import { getCalendarSnapshot } from '../../lib/calendar.ts';

export const GET: APIRoute = async ({ request }) => {
  try {
    const { events, etag } = getCalendarSnapshot();
    const ifNoneMatch = request.headers.get('if-none-match');

    if (ifNoneMatch && ifNoneMatch === etag) {
      return new Response(null, {
        status: 304,
        headers: {
          'ETag': etag,
          'Cache-Control': 'no-cache'
        }
      });
    }

    return new Response(JSON.stringify(events), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'ETag': etag,
        'Cache-Control': 'no-cache'
      }
    });
  } catch {
    return new Response(JSON.stringify([]), {
      status: 503,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
      }
    });
  }
};

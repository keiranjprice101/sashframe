import type { APIRoute } from 'astro';
import { loadShifterEvents, getShifterFingerprint } from '../../lib/shifter.ts';

export const GET: APIRoute = async ({ request }) => {
  try {
    const fingerprint = getShifterFingerprint();
    const etag = `"${fingerprint}"`;
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

    const events = loadShifterEvents();
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
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
      }
    });
  }
};

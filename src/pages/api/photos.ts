import type { APIRoute } from 'astro';
import fs from 'node:fs';
import path from 'node:path';

function getManifestPath(): string {
  return process.env.PHOTO_MANIFEST || path.resolve('data/photos/manifest.json');
}

export const GET: APIRoute = async ({ request }) => {
  const manifestPath = getManifestPath();
  
  if (!fs.existsSync(manifestPath)) {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
      }
    });
  }

  try {
    const stat = fs.statSync(manifestPath);
    const etag = `"${stat.mtimeMs.toString(36)}-${stat.size.toString(36)}"`;
    const ifNoneMatch = request.headers.get('if-none-match');

    if (ifNoneMatch && ifNoneMatch === etag) {
      return new Response(null, {
        status: 304,
        headers: {
          'ETag': etag,
          'Cache-Control': 'no-cache',
        }
      });
    }

    const raw = fs.readFileSync(manifestPath, 'utf-8');
    // Ensure valid JSON before returning
    JSON.parse(raw);
    return new Response(raw, {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'ETag': etag,
        'Cache-Control': 'no-cache',
      }
    });
  } catch {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
      }
    });
  }
};

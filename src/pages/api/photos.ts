import type { APIRoute } from 'astro';
import fs from 'node:fs';
import path from 'node:path';

function getManifestPath(): string {
  if (process.env.PHOTO_MANIFEST && fs.existsSync(process.env.PHOTO_MANIFEST)) {
    return process.env.PHOTO_MANIFEST;
  }
  const systemPath = '/var/lib/home-calendar/photos/manifest.json';
  if (fs.existsSync(systemPath)) {
    return systemPath;
  }
  return path.resolve('data/photos/manifest.json');
}

export const GET: APIRoute = async () => {
  const manifestPath = getManifestPath();
  
  if (!fs.existsSync(manifestPath)) {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store, no-cache, must-revalidate'
      }
    });
  }

  try {
    const raw = fs.readFileSync(manifestPath, 'utf-8');
    // Ensure valid JSON before returning
    JSON.parse(raw);
    return new Response(raw, {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store, no-cache, must-revalidate'
      }
    });
  } catch (err) {
    return new Response(JSON.stringify([]), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store, no-cache, must-revalidate'
      }
    });
  }
};

import type { APIRoute } from 'astro';
import fs from 'node:fs';
import path from 'node:path';

function getProcessedDir(): string {
  if (process.env.PHOTO_OUTPUT_DIR) {
    return process.env.PHOTO_OUTPUT_DIR;
  }
  const sashframeDir = '/var/lib/sashframe/photos/processed';
  if (fs.existsSync(sashframeDir)) {
    return sashframeDir;
  }
  const legacyDir = '/var/lib/home-calendar/photos/processed';
  if (fs.existsSync(legacyDir)) {
    return legacyDir;
  }
  return path.resolve('data/photos/processed');
}

export const GET: APIRoute = async ({ params }) => {
  const imageName = params.image;
  if (!imageName) return new Response('Not found', { status: 404 });
  
  // Security: prevent directory traversal
  const cleanImageName = path.basename(imageName);
  const processedDir = getProcessedDir();
  const filePath = path.resolve(processedDir, cleanImageName);
  
  if (!fs.existsSync(filePath)) {
    return new Response('Not found', { status: 404 });
  }
  
  const buffer = fs.readFileSync(filePath);
  const ext = path.extname(cleanImageName).toLowerCase();
  const mimeType = ext === '.webp' ? 'image/webp' : ext === '.png' ? 'image/png' : 'image/jpeg';
  
  return new Response(buffer, {
    headers: {
      'Content-Type': mimeType,
      'Cache-Control': 'public, max-age=3600'
    }
  });
};

import type { APIRoute, GetStaticPaths } from 'astro';
import fs from 'node:fs';
import path from 'node:path';

function getProcessedDir(): string {
  if (process.env.PHOTO_OUTPUT_DIR && fs.existsSync(process.env.PHOTO_OUTPUT_DIR)) {
    return process.env.PHOTO_OUTPUT_DIR;
  }
  const systemDir = '/var/lib/home-calendar/photos/processed';
  if (fs.existsSync(systemDir)) {
    return systemDir;
  }
  return path.resolve('data/photos/processed');
}

export const getStaticPaths: GetStaticPaths = async () => {
  const processedDir = getProcessedDir();
  if (!fs.existsSync(processedDir)) return [];
  const files = fs.readdirSync(processedDir);
  return files.filter((f: string) => !f.startsWith('.')).map((file: string) => ({
    params: { image: file }
  }));
};

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

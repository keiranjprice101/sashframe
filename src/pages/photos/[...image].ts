import type { APIRoute, GetStaticPaths } from 'astro';
import fs from 'node:fs';
import path from 'node:path';

export const getStaticPaths: GetStaticPaths = async () => {
  const processedDir = path.resolve('data/photos/processed');
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
  const filePath = path.resolve('data/photos/processed', cleanImageName);
  
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

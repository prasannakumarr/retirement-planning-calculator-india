import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

/*
 * Vite configuration.
 *
 * The only non-default piece is the /api proxy. The Svelte dev server runs on
 * :5173 and the Haskell backend on :8080, which makes every API call
 * cross-origin. Proxying /api through the dev server keeps the browser seeing
 * a same-origin request, so frontend code can use plain relative URLs and
 * nothing has to change when the app is built and served for real.
 *
 * (The backend also sends permissive CORS headers, so direct calls work too —
 * the proxy just means the frontend never has to care.)
 */
export default defineConfig({
  plugins: [svelte()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true,
      },
    },
  },
});

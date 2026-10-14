/*
 * api.js — the only module that knows the backend exists.
 *
 * WHERE THIS FITS: sits between App.svelte and the Haskell server. Components
 * call these two functions and get back either data or a thrown Error with a
 * human-readable message; they never touch fetch, status codes or JSON.
 *
 * IMPORTANT: no retirement arithmetic happens anywhere in the frontend. Every
 * number on screen — including every chart coordinate — is computed by the
 * Haskell backend and simply drawn here. That is a deliberate constraint: it
 * means there is exactly one implementation of the formulas, so the charts can
 * never disagree with the numbers printed beside them.
 */

// Vite proxies /api to the Haskell server on :8080 in development (see
// vite.config.js), so a relative URL works in both dev and a built bundle.
const BASE = '/api';

/**
 * Shared response handling.
 *
 * The backend returns {errorMessage} with a 400 for inputs it refuses — those
 * messages are written for the user ("Retirement age must be at least one year
 * after your current age") so they are surfaced verbatim rather than replaced
 * with something generic.
 */
async function handle(response) {
  if (response.ok) return response.json();

  let message = `Request failed (${response.status})`;
  try {
    const body = await response.json();
    if (body && body.errorMessage) message = body.errorMessage;
  } catch {
    // Response wasn't JSON — keep the status-code message.
  }
  throw new Error(message);
}

/**
 * The starting scenario, fetched rather than hard-coded.
 *
 * The defaults live in the Haskell `defaultInput` next to the maths that
 * consumes them, so there is a single source of truth for "what does this
 * calculator assume". Changing an assumption means changing one Haskell
 * record, not hunting through Svelte components.
 */
export async function fetchDefaults() {
  return handle(await fetch(`${BASE}/defaults`));
}

/** Run a full projection. Returns {summary, accumulation, drawdown, echoedInput}. */
export async function calculate(input) {
  const response = await fetch(`${BASE}/calculate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  return handle(response);
}

const BASE = '/api';

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

export async function fetchDefaults() {
  return handle(await fetch(`${BASE}/defaults`));
}

export async function calculate(input) {
  const response = await fetch(`${BASE}/calculate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  return handle(response);
}

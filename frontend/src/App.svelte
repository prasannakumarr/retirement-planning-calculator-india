<script>
  import { onMount } from 'svelte';
  import { fetchDefaults, calculate } from './lib/api.js';
  import InputPanel from './lib/InputPanel.svelte';
  import ResultsPanel from './lib/ResultsPanel.svelte';

  let input = $state(null);
  let defaults = $state(null);
  let result = $state(null);
  let error = $state(null);
  let busy = $state(false);
  let theme = $state('system');

  onMount(async () => {
    try {
      defaults = await fetchDefaults();
      input = { ...defaults };
    } catch (e) {
      error =
        'Could not reach the calculator backend. Start it with `cabal run` ' +
        'in the backend directory, then reload this page.';
    }
  });

  let timer;
  let requestId = 0;

  $effect(() => {
    if (!input) return;

    // Touch every field so Svelte re-runs this effect on any change.
    const snapshot = JSON.stringify(input);

    clearTimeout(timer);
    timer = setTimeout(async () => {
      const mine = ++requestId;
      busy = true;
      try {
        const next = await calculate(JSON.parse(snapshot));
        if (mine === requestId) {
          result = next;
          error = null;
        }
      } catch (e) {
        if (mine === requestId) error = e.message;
      } finally {
        if (mine === requestId) busy = false;
      }
    }, 180);
  });

  function reset() {
    if (defaults) input = { ...defaults };
  }

  function cycleTheme() {
    theme = theme === 'system' ? 'light' : theme === 'light' ? 'dark' : 'system';
    const root = document.documentElement;
    if (theme === 'system') root.removeAttribute('data-theme');
    else root.setAttribute('data-theme', theme);
  }
</script>

<div class="shell">
  <header>
    <div class="titles">
      <h1>Retirement calculator</h1>
      <p>
        A simple projection for the Indian context. Change anything on the left
        and the numbers follow.
      </p>
    </div>

    <div class="header-right">
      <span class="busy" class:on={busy} aria-live="polite">
        {busy ? 'Calculating…' : ''}
      </span>
      <button class="theme" onclick={cycleTheme} title="Switch theme">
        {theme === 'system' ? 'Auto' : theme === 'light' ? 'Light' : 'Dark'}
      </button>
    </div>
  </header>

  {#if error && !result}
    <div class="error">{error}</div>
  {/if}

  {#if input}
    <div class="layout">
      <aside>
        <InputPanel bind:input onReset={reset} />
      </aside>

      <main>
        {#if error}
          <div class="error inline">{error}</div>
        {/if}

        {#if result}
          <ResultsPanel {result} />
        {/if}
      </main>
    </div>
  {:else if !error}
    <p class="loading">Loading…</p>
  {/if}

  <footer>
    <p>
      Estimates only, not financial advice. Tax is estimated from today's slabs,
      healthcare inflates faster than other spending, and returns are assumed
      to arrive smoothly rather than in the lumpy order real markets deliver them.
    </p>
  </footer>
</div>

<style>
  .shell {
    max-width: 1340px;
    margin: 0 auto;
    padding: 24px 20px 56px;
  }

  header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
    margin-bottom: 22px;
  }

  h1 {
    font-size: 20px;
    letter-spacing: -0.01em;
  }

  .titles p {
    margin: 4px 0 0;
    font-size: 13px;
    color: var(--text-secondary);
    max-width: 60ch;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .busy {
    font-size: 12px;
    color: var(--text-muted);
    opacity: 0;
    transition: opacity 120ms;
  }
  .busy.on { opacity: 1; }

  .theme {
    background: transparent;
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 5px 13px;
    font: inherit;
    font-size: 12px;
    color: var(--text-secondary);
    cursor: pointer;
  }
  .theme:hover { background: var(--surface-sunken); }

  .layout {
    display: grid;
    grid-template-columns: 330px minmax(0, 1fr);
    gap: 26px;
    align-items: start;
  }

  aside {
    position: sticky;
    top: 20px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
    max-height: calc(100vh - 40px);
    overflow-y: auto;
  }

  main { min-width: 0; }

  .error {
    background: var(--surface);
    border: 1px solid var(--status-critical);
    border-left-width: 3px;
    border-radius: var(--radius);
    padding: 12px 16px;
    font-size: 13px;
    color: var(--text-primary);
  }
  .inline { margin-bottom: 16px; }

  .loading { color: var(--text-muted); }

  footer {
    margin-top: 32px;
    padding-top: 18px;
    border-top: 1px solid var(--border);
  }
  footer p {
    margin: 0;
    font-size: 12px;
    line-height: 1.6;
    color: var(--text-muted);
    max-width: 90ch;
  }
  code {
    font-size: 11.5px;
    background: var(--surface-sunken);
    padding: 1px 5px;
    border-radius: 4px;
  }

  @media (max-width: 900px) {
    .layout { grid-template-columns: 1fr; }
    aside {
      position: static;
      max-height: none;
    }
  }
</style>

<script>
  /*
   * App.svelte — the root component.
   *
   * WHERE THIS FITS: the top of the tree. It owns the one piece of state that
   * matters (the `input` object), fetches results from the Haskell backend
   * whenever that state changes, and hands the result to ResultsPanel.
   *
   * The central design decision is that there is no "Calculate" button. The
   * projection re-runs automatically, debounced, as soon as any field changes.
   * The whole value of this tool is seeing what moves when an assumption
   * moves, and a submit button puts a wall between the question and the
   * answer. The previous result stays on screen while a new one is in flight,
   * so the charts never flash empty mid-drag.
   *
   * All arithmetic lives in Haskell. This file decides *when* to ask, never
   * *what the answer is*.
   */
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
      // Clone, so "Reset to defaults" always has a pristine copy to go back to.
      input = { ...defaults };
    } catch (e) {
      error =
        'Could not reach the calculator backend. Start it with `cabal run` ' +
        'in the backend directory, then reload this page.';
    }
  });

  /*
   * Debounced recalculation.
   *
   * Dragging a slider fires an input event per pixel; without the delay that
   * is a hundred round trips a second. 180ms is short enough that the result
   * still feels attached to the drag.
   *
   * `requestId` guards against out-of-order responses: a slow earlier request
   * must not overwrite the result of a faster later one, which would leave the
   * charts showing numbers that do not match the form.
   */
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
      <!-- A quiet activity indicator rather than a blocking spinner: the old
           result stays readable while the new one is computed. -->
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
          <!-- A validation failure keeps the last good result on screen and
               explains what is wrong, rather than blanking the page. -->
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
      Every number here is computed by the Haskell backend; this page only draws
      them. The model estimates tax from today's slabs, gives healthcare its
      own faster inflation, and assumes returns arrive smoothly rather than in
      the lumpy order real markets deliver them. Read
      <code>ASSUMPTIONS.md</code> before you make a decision on any of this — it
      lists what the calculator does, what it deliberately leaves out, and where
      it is most likely to be wrong.
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

  /* Two columns on a desktop, stacked on anything narrower. The form column
     is fixed-width because its fields do not benefit from extra space; the
     results column takes everything that is left, because charts do. */
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

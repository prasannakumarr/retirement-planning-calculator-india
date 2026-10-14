<script>
  /*
   * StatTile.svelte — one headline number with a label and an optional note.
   *
   * WHERE THIS FITS: used across the top of ResultsPanel.svelte as a KPI row.
   *
   * A single number is not a chart. Four of these in a row communicate the
   * result far faster than a four-bar bar chart would, which is why the
   * headline figures are tiles and only the genuinely comparative or
   * time-varying quantities get plotted.
   */
  let {
    label,
    value,
    /** Small print under the value — context, not decoration. */
    note = '',
    /** Tints the value for good/bad. Leave unset for neutral figures. */
    tone = 'neutral',
    /** Renders the value larger, for the one figure the page leads with. */
    hero = false,
  } = $props();
</script>

<div class="tile" class:hero>
  <div class="label">{label}</div>
  <!-- Proportional figures deliberately: tabular-nums gives every digit the
       width of a zero, which makes a large number look gappy. Tabular is for
       columns that must align, i.e. the table. -->
  <div class="value" data-tone={tone}>{value}</div>
  {#if note}<div class="note">{note}</div>{/if}
</div>

<style>
  .tile {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 14px 16px;
    display: grid;
    gap: 3px;
    align-content: start;
  }

  .label {
    font-size: 12px;
    color: var(--text-secondary);
  }

  .value {
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.01em;
    color: var(--text-primary);
  }

  .hero .value { font-size: 48px; line-height: 1.05; }

  /* Status colours are reserved and never reused as series colours. These are
     the TEXT steps, which clear contrast against the surface — the brighter
     mark steps are for dots and fills only. The tile's label always states the
     meaning in words too, so nothing rests on hue alone. */
  .value[data-tone='good']     { color: var(--status-good-text); }
  .value[data-tone='warning']  { color: var(--status-warning-text); }
  .value[data-tone='serious']  { color: var(--status-warning-text); }
  .value[data-tone='critical'] { color: var(--status-critical-text); }

  .note {
    font-size: 11.5px;
    line-height: 1.45;
    color: var(--text-muted);
  }
</style>

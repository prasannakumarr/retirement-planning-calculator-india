<script>
  /*
   * BarChart.svelte — horizontal bars, optionally stacked.
   *
   * WHERE THIS FITS: used once, for the "what you need vs what you will have"
   * comparison on the results page. Horizontal rather than vertical because
   * the category names are sentences ("Need — safe withdrawal method"), and
   * horizontal bars give long labels room without rotating them.
   *
   * Mark specs followed here: bars capped at 24px so the band keeps some air,
   * a 4px rounded cap on the data end with the baseline end left square, and
   * a 2px gap in the surface colour between stacked segments. The gap is what
   * separates touching segments — never a stroke, which would add ink that
   * isn't data.
   */
  import { compactRupees } from '../format.js';

  let {
    /** [{ label, segments: [{ name, value, color }] }] */
    bars = [],
    /** Shown above the plot when segments carry distinct identities. */
    showLegend = true,
    formatValue = compactRupees,
    barThickness = 22,
    rowHeight = 46,
  } = $props();

  let width = $state(640);

  // Left margin holds the category labels; right margin holds the total at
  // the bar tip. Both are reserved up front so no text is ever clipped.
  const M = $derived({
    top: 4,
    right: Math.min(96, Math.max(72, width * 0.18)),
    bottom: 26,
    left: width < 520 ? 0 : 168,
  });

  // On a narrow screen the label moves above its bar instead of beside it,
  // which keeps the plot usable at phone widths.
  const stackedLabels = $derived(M.left === 0);
  const rowH = $derived(stackedLabels ? rowHeight + 18 : rowHeight);

  const height = $derived(bars.length * rowH + M.top + M.bottom);
  const plotW = $derived(Math.max(10, width - M.left - M.right));

  const totals = $derived(
    bars.map((b) => b.segments.reduce((sum, s) => sum + Math.max(0, s.value), 0))
  );
  const maxTotal = $derived(Math.max(1, ...totals));

  const scale = $derived((v) => (v / maxTotal) * plotW);

  /** Legend entries, de-duplicated across bars and kept in first-seen order. */
  const legendItems = $derived.by(() => {
    const seen = new Map();
    for (const b of bars) {
      for (const s of b.segments) {
        if (s.name && !seen.has(s.name)) seen.set(s.name, s.color);
      }
    }
    return [...seen].map(([name, color]) => ({ name, color }));
  });

  /**
   * A rectangle with its right-hand (data) end rounded and its left-hand
   * (baseline) end square. Interior segments of a stack pass r = 0, because
   * only the end of the whole bar is a data end.
   */
  function barPath(x, y, w, h, r) {
    const rr = Math.max(0, Math.min(r, w, h / 2));
    if (rr === 0) return `M${x},${y} h${w} v${h} h${-w} Z`;
    return (
      `M${x},${y} H${x + w - rr} Q${x + w},${y} ${x + w},${y + rr} ` +
      `V${y + h - rr} Q${x + w},${y + h} ${x + w - rr},${y + h} H${x} Z`
    );
  }

  let hover = $state(null);
</script>

<div class="chart" bind:clientWidth={width}>
  {#if showLegend && legendItems.length > 1}
    <div class="legend">
      {#each legendItems as item (item.name)}
        <span class="legend-item">
          <span class="swatch" style:background={item.color}></span>
          {item.name}
        </span>
      {/each}
    </div>
  {/if}

  <svg {height} width="100%" role="img" aria-label="Required versus projected corpus">
    {#each bars as bar, i (bar.label)}
      {@const labelOffset = stackedLabels ? 18 : 0}
      {@const top = M.top + i * rowH + labelOffset}
      {@const barY = top + (rowHeight - barThickness) / 2}

      <!-- Category label: beside the bar when there is room, above it when
           there is not. Text always uses text tokens, never a series colour. -->
      {#if stackedLabels}
        <text x="0" y={top - 6} class="cat-label cat-label-above">{bar.label}</text>
      {:else}
        <text x={M.left - 12} y={barY + barThickness / 2} class="cat-label">
          {bar.label}
        </text>
      {/if}

      <!-- Segments. `cursor` walks left to right; each segment is inset by 2px
           on its left edge so the surface shows through between them. -->
      {#each bar.segments as seg, j (seg.name)}
        {@const prior = bar.segments
          .slice(0, j)
          .reduce((sum, s) => sum + Math.max(0, s.value), 0)}
        {@const gap = j === 0 ? 0 : 2}
        {@const x = M.left + scale(prior) + gap}
        {@const w = Math.max(0, scale(Math.max(0, seg.value)) - gap)}
        {@const isLast = j === bar.segments.length - 1}

        {#if w > 0}
          <path
            d={barPath(x, barY, w, barThickness, isLast ? 4 : 0)}
            fill={seg.color}
            onmouseenter={() => (hover = { bar: bar.label, ...seg })}
            onmouseleave={() => (hover = null)}
            role="presentation"
          />
        {/if}
      {/each}

      <!-- The total, at the tip. Labelling the tip rather than each segment
           keeps the chart readable; per-segment values live in the tooltip
           and in the table below. -->
      <text
        x={M.left + scale(totals[i]) + 10}
        y={barY + barThickness / 2}
        class="value-label"
      >
        {formatValue(totals[i])}
      </text>
    {/each}

    <!-- Single baseline all bars grow from. -->
    <line
      x1={M.left} x2={M.left}
      y1={M.top} y2={M.top + bars.length * rowH}
      class="axis"
    />
  </svg>

  {#if hover}
    <div class="tooltip">
      <strong>{hover.bar}</strong>
      <span class="tooltip-row">
        <span class="swatch" style:background={hover.color}></span>
        {hover.name}
        <span class="tooltip-value">{formatValue(hover.value)}</span>
      </span>
    </div>
  {/if}
</div>

<style>
  .chart { position: relative; width: 100%; }

  svg { display: block; overflow: visible; }

  .axis { stroke: var(--baseline); stroke-width: 1; }

  .cat-label {
    fill: var(--text-secondary);
    font-size: 12px;
    text-anchor: end;
    dominant-baseline: middle;
  }
  .cat-label-above { text-anchor: start; dominant-baseline: auto; }

  .value-label {
    fill: var(--text-primary);
    font-size: 12px;
    font-weight: 600;
    dominant-baseline: middle;
    font-variant-numeric: tabular-nums;
  }

  .legend {
    display: flex;
    flex-wrap: wrap;
    gap: 14px;
    margin-bottom: 10px;
    font-size: 12px;
    color: var(--text-secondary);
  }
  .legend-item { display: inline-flex; align-items: center; gap: 6px; }

  .swatch { width: 10px; height: 10px; border-radius: 2px; flex: none; }

  .tooltip {
    position: absolute;
    top: 0;
    right: 0;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 8px 10px;
    font-size: 12px;
    pointer-events: none;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
    display: grid;
    gap: 4px;
    z-index: 2;
  }
  .tooltip-row {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--text-secondary);
  }
  .tooltip-value {
    margin-left: 10px;
    font-weight: 600;
    color: var(--text-primary);
    font-variant-numeric: tabular-nums;
  }
</style>

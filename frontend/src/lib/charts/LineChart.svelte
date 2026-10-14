<script>
  /*
   * LineChart.svelte — a reusable multi-series line/area chart.
   *
   * WHERE THIS FITS: used twice on the results page — once for the corpus
   * growing up to retirement (two series: your path vs the on-track path),
   * and once for the corpus being spent down through retirement (one series,
   * drawn as an area).
   *
   * It is hand-rolled SVG rather than a charting library. For two chart types
   * a library would be more code to configure than to write, and drawing the
   * marks directly is what makes it possible to follow the specs exactly:
   * 2px lines, >=8px end markers with a 2px surface ring so they stay legible
   * where they overlap, hairline gridlines that recede, and a hover layer that
   * is present by default rather than bolted on.
   *
   * The component is purely presentational — it receives points and draws
   * them. Every value it plots was computed by the Haskell backend. With
   * `stacked`, each series is drawn on top of the ones before it; adding the
   * bands up to find where each one sits is drawing, not financial arithmetic,
   * and the tooltip always shows each series' own value rather than the sum.
   */
  import { compactNumber } from '../format.js';

  let {
    /** [{ name, color, points: [{x, y}], area? }] — drawn in order. */
    series = [],
    /** Horizontal reference lines: [{ y, label, color }]. */
    rules = [],
    height = 280,
    xLabel = '',
    yLabel = '',
    formatY = compactNumber,
    formatX = (v) => String(v),
    /** Tooltip heading, given the x value of the hovered column. */
    tooltipTitle = (x) => String(x),
    /** Draw the series as bands stacked on one another (part-to-whole). */
    stacked = false,
  } = $props();

  /*
   * Where each series is drawn. Unstacked, that is just its own points.
   * Stacked, each point is lifted by the series below it, and `base` records
   * the bottom edge of the band so the fill runs between the two.
   */
  const drawn = $derived.by(() => {
    if (!stacked) return series.map((s) => ({ ...s, base: null }));
    let below = null;
    return series.map((s) => {
      const base = s.points.map((p, i) => (below ? below[i].y : 0));
      const points = s.points.map((p, i) => ({ x: p.x, y: base[i] + p.y }));
      below = points;
      return { ...s, points, base };
    });
  });

  // Measured rather than assumed, so the chart reflows correctly inside a
  // resizing grid column and on a phone.
  let width = $state(640);

  // Left margin has to clear the widest y tick ("12.5 Cr"), and the right
  // margin leaves room for end labels without letting them overflow the SVG.
  const M = { top: 12, right: 64, bottom: 34, left: 52 };

  const plotW = $derived(Math.max(10, width - M.left - M.right));
  const plotH = $derived(Math.max(10, height - M.top - M.bottom));

  const allPoints = $derived(drawn.flatMap((s) => s.points));

  const xMin = $derived(Math.min(...allPoints.map((p) => p.x)));
  const xMax = $derived(Math.max(...allPoints.map((p) => p.x)));

  // The y scale always starts at zero. A truncated baseline exaggerates
  // differences, and on a corpus chart that would overstate how far ahead or
  // behind someone is — the exact thing this app must not do.
  const yMaxRaw = $derived(
    Math.max(0, ...allPoints.map((p) => p.y), ...rules.map((r) => r.y))
  );

  /** Round axis bounds out to human numbers (0 / 2 Cr / 4 Cr …). */
  function niceTicks(max, count = 5) {
    if (!isFinite(max) || max <= 0) return [0, 1];
    const raw = max / count;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const n = raw / mag;
    // 2.5 is in the ladder deliberately. Without it a maximum of 12.1 Cr
    // snaps to a step of 5 and an axis topping out at 15 Cr — a quarter of the
    // plot left empty above the data. With it the axis tops out at 12.5 Cr.
    const step = (n >= 5 ? 10 : n >= 2.5 ? 5 : n >= 2 ? 2.5 : n >= 1 ? 2 : 1) * mag;
    const ticks = [];
    for (let v = 0; v <= max + step * 1e-6; v += step) ticks.push(v);
    // Guarantee the top tick is at or above the data.
    if (ticks[ticks.length - 1] < max) ticks.push(ticks[ticks.length - 1] + step);
    return ticks;
  }

  const yTicks = $derived(niceTicks(yMaxRaw));
  const yMax = $derived(yTicks[yTicks.length - 1] || 1);

  const sx = $derived((x) =>
    M.left + (xMax === xMin ? 0 : ((x - xMin) / (xMax - xMin)) * plotW)
  );
  const sy = $derived((y) => M.top + plotH - (y / yMax) * plotH);

  /** X ticks at round ages, thinned so labels never overlap on a phone. */
  const xTicks = $derived.by(() => {
    const span = xMax - xMin;
    if (span <= 0) return [xMin];
    const target = Math.max(2, Math.floor(plotW / 64));
    const step = Math.max(1, Math.ceil(span / target / 5) * 5);
    const out = [];
    for (let v = xMin; v <= xMax; v += step) out.push(v);
    if (out[out.length - 1] !== xMax) out.push(xMax);
    return out;
  });

  function path(points) {
    return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${sx(p.x)},${sy(p.y)}`).join(' ');
  }

  /** A band between a series' points and the top of the series below it. */
  function bandPath(points, base) {
    if (!points.length) return '';
    const top = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${sx(p.x)},${sy(p.y)}`).join(' ');
    const bottom = points
      .map((p, i) => ({ x: p.x, y: base[i] }))
      .reverse()
      .map((p) => `L${sx(p.x)},${sy(p.y)}`)
      .join(' ');
    return `${top} ${bottom} Z`;
  }

  function areaPath(points) {
    if (!points.length) return '';
    const base = M.top + plotH;
    return (
      `M${sx(points[0].x)},${base} ` +
      points.map((p) => `L${sx(p.x)},${sy(p.y)}`).join(' ') +
      ` L${sx(points[points.length - 1].x)},${base} Z`
    );
  }

  /*
   * End labels are only drawn when they demonstrably fit. Two converging
   * lines produce two labels in the same place, and nudging them apart would
   * detach each label from its line — so when they are closer than a line
   * height, the labels are dropped entirely and the legend plus the hover
   * tooltip carry the identity instead.
   */
  const endLabels = $derived.by(() => {
    // A stacked band's top edge is a running total, so labelling it would
    // print a number that belongs to no single series.
    if (width < 420 || stacked) return [];
    const ends = series
      .filter((s) => s.points.length)
      .map((s) => ({
        name: s.name,
        color: s.color,
        y: sy(s.points[s.points.length - 1].y),
        value: s.points[s.points.length - 1].y,
      }));
    for (let i = 0; i < ends.length; i++) {
      for (let j = i + 1; j < ends.length; j++) {
        if (Math.abs(ends[i].y - ends[j].y) < 18) return [];
      }
    }
    return ends;
  });

  // ---------------------------------------------------------------- hover --

  let hoverIndex = $state(null);
  let pointerX = $state(0);

  // Every series shares the same x values (one row per year), so a single
  // index identifies the whole column.
  const xValues = $derived(series[0] ? series[0].points.map((p) => p.x) : []);

  function onMove(event) {
    const box = event.currentTarget.getBoundingClientRect();
    const px = event.clientX - box.left;
    pointerX = px;
    if (!xValues.length) return;

    // Nearest column, not the one under the cursor — a 1px-wide hit target
    // would be unusable.
    let best = 0;
    let bestDist = Infinity;
    for (let i = 0; i < xValues.length; i++) {
      const d = Math.abs(sx(xValues[i]) - px);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    hoverIndex = best;
  }

  const hoverX = $derived(hoverIndex === null ? 0 : sx(xValues[hoverIndex]));

  // Keep the tooltip inside the chart instead of letting it run off the edge.
  const tooltipLeft = $derived(Math.min(Math.max(hoverX, 70), width - 70));
  const tooltipFlip = $derived(hoverX > width * 0.6);
</script>

<!--
  The wrapper is position:relative so the HTML tooltip can be absolutely
  positioned over the SVG. Tooltips are HTML rather than SVG text because they
  need wrapping, padding and a background, all of which are painful in SVG.
-->
<div class="chart" bind:clientWidth={width}>
  {#if series.length > 1}
    <!-- A legend is always present for two or more series: identity must
         never depend on the reader matching colours from memory. -->
    <div class="legend">
      {#each series as s (s.name)}
        <span class="legend-item">
          <span class="swatch" style:background={s.color}></span>
          {s.name}
        </span>
      {/each}
    </div>
  {/if}

  <svg
    {height}
    width="100%"
    role="img"
    aria-label={yLabel}
    onmousemove={onMove}
    onmouseleave={() => (hoverIndex = null)}
  >
    <!-- Gridlines: hairline, solid, one step off the surface. They carry the
         values that are not directly labelled, so they stay — but they must
         never compete with the data. -->
    {#each yTicks as t (t)}
      <line x1={M.left} x2={M.left + plotW} y1={sy(t)} y2={sy(t)} class="grid" />
      <text x={M.left - 8} y={sy(t)} class="tick tick-y">{formatY(t)}</text>
    {/each}

    {#each xTicks as t (t)}
      <text x={sx(t)} y={M.top + plotH + 20} class="tick tick-x">{formatX(t)}</text>
    {/each}

    <!-- Baseline sits above the gridlines so it reads as the axis. -->
    <line
      x1={M.left} x2={M.left + plotW}
      y1={M.top + plotH} y2={M.top + plotH}
      class="axis"
    />

    <!-- Reference rules (e.g. "the corpus you need") are dashed-free hairlines
         in the series colour, labelled directly so they never rely on hue. -->
    {#each rules as r (r.label)}
      <line
        x1={M.left} x2={M.left + plotW}
        y1={sy(r.y)} y2={sy(r.y)}
        class="rule" style:stroke={r.color}
      />
      <text x={M.left + 6} y={sy(r.y) - 6} class="rule-label">{r.label}</text>
    {/each}

    {#if stacked}
      <!-- Solid bands, each separated from the next by a 2px line in the
           surface colour — a gap, not a stroke, so it adds no ink. -->
      {#each drawn as s (s.name)}
        <path d={bandPath(s.points, s.base)} fill={s.color} opacity="0.9" />
      {/each}
      {#each drawn as s (s.name)}
        <path
          d={path(s.points)}
          fill="none"
          stroke="var(--surface)"
          stroke-width="2"
          stroke-linejoin="round"
        />
      {/each}
    {:else}
      <!-- Area washes first, so lines and markers sit on top of them. -->
      {#each drawn as s (s.name)}
        {#if s.area}
          <path d={areaPath(s.points)} fill={s.color} opacity="0.1" />
        {/if}
      {/each}

      {#each drawn as s (s.name)}
        <path
          d={path(s.points)}
          fill="none"
          stroke={s.color}
          stroke-width="2"
          stroke-linejoin="round"
          stroke-linecap="round"
        />
      {/each}
    {/if}

    <!-- Hover crosshair, drawn under the markers. -->
    {#if hoverIndex !== null}
      <line x1={hoverX} x2={hoverX} y1={M.top} y2={M.top + plotH} class="crosshair" />
      {#each drawn as s (s.name)}
        {#if s.points[hoverIndex]}
          <!-- The surface-coloured ring is what keeps a dot readable where it
               crosses another line, and it doubles the hit target. -->
          <circle
            cx={sx(s.points[hoverIndex].x)}
            cy={sy(s.points[hoverIndex].y)}
            r="4"
            fill={s.color}
            stroke="var(--surface)"
            stroke-width="2"
          />
        {/if}
      {/each}
    {/if}

    <!-- End markers and labels. Text wears text tokens, never the series
         colour — a colour light enough to be a good mark is too light to be
         readable type. The small coloured dot beside it carries identity. -->
    {#each endLabels as e (e.name)}
      <circle
        cx={M.left + plotW} cy={e.y} r="4"
        fill={e.color} stroke="var(--surface)" stroke-width="2"
      />
      <text x={M.left + plotW + 10} y={e.y + 4} class="end-label">
        {formatY(e.value)}
      </text>
    {/each}
  </svg>

  {#if xLabel}<div class="axis-title">{xLabel}</div>{/if}

  {#if hoverIndex !== null}
    <div
      class="tooltip"
      class:flip={tooltipFlip}
      style:left="{tooltipLeft}px"
    >
      <div class="tooltip-title">{tooltipTitle(xValues[hoverIndex])}</div>
      {#each series as s (s.name)}
        {#if s.points[hoverIndex]}
          <div class="tooltip-row">
            <span class="swatch" style:background={s.color}></span>
            <span class="tooltip-name">{s.name}</span>
            <span class="tooltip-value">{formatY(s.points[hoverIndex].y)}</span>
          </div>
        {/if}
      {/each}
    </div>
  {/if}
</div>

<style>
  .chart {
    position: relative;
    width: 100%;
  }

  svg { display: block; overflow: visible; }

  .grid   { stroke: var(--gridline); stroke-width: 1; }
  .axis   { stroke: var(--baseline); stroke-width: 1; }
  .rule   { stroke-width: 1; opacity: 0.75; }
  .crosshair { stroke: var(--baseline); stroke-width: 1; }

  .tick {
    fill: var(--text-muted);
    font-size: 11px;
    font-variant-numeric: tabular-nums;
  }
  .tick-y { text-anchor: end; dominant-baseline: middle; }
  .tick-x { text-anchor: middle; }

  .rule-label { fill: var(--text-secondary); font-size: 11px; }

  .end-label {
    fill: var(--text-secondary);
    font-size: 11px;
    font-weight: 600;
  }

  .legend {
    display: flex;
    flex-wrap: wrap;
    gap: 14px;
    margin-bottom: 8px;
    font-size: 12px;
    color: var(--text-secondary);
  }
  .legend-item { display: inline-flex; align-items: center; gap: 6px; }

  .swatch {
    width: 10px;
    height: 10px;
    border-radius: 2px;
    flex: none;
  }

  .axis-title {
    text-align: center;
    font-size: 11px;
    color: var(--text-muted);
    margin-top: 2px;
  }

  .tooltip {
    position: absolute;
    top: 8px;
    transform: translateX(-50%);
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 8px 10px;
    font-size: 12px;
    pointer-events: none;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
    white-space: nowrap;
    z-index: 2;
  }
  .tooltip.flip { transform: translateX(-100%); }

  .tooltip-title {
    font-weight: 600;
    margin-bottom: 4px;
    color: var(--text-primary);
  }
  .tooltip-row {
    display: flex;
    align-items: center;
    gap: 6px;
    color: var(--text-secondary);
  }
  .tooltip-name { margin-right: 10px; }
  .tooltip-value {
    margin-left: auto;
    font-variant-numeric: tabular-nums;
    color: var(--text-primary);
    font-weight: 600;
  }
</style>

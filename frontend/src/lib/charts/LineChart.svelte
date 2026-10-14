<script>
  import { compactNumber } from '../format.js';

  let {
    series = [],
    rules = [],
    height = 280,
    xLabel = '',
    yLabel = '',
    formatY = compactNumber,
    formatX = (v) => String(v),
    tooltipTitle = (x) => String(x),
    stacked = false,
  } = $props();

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

  let width = $state(640);

  const M = { top: 12, right: 64, bottom: 34, left: 52 };

  const plotW = $derived(Math.max(10, width - M.left - M.right));
  const plotH = $derived(Math.max(10, height - M.top - M.bottom));

  const allPoints = $derived(drawn.flatMap((s) => s.points));

  const xMin = $derived(Math.min(...allPoints.map((p) => p.x)));
  const xMax = $derived(Math.max(...allPoints.map((p) => p.x)));

  const yMaxRaw = $derived(
    Math.max(0, ...allPoints.map((p) => p.y), ...rules.map((r) => r.y))
  );

  function niceTicks(max, count = 5) {
    if (!isFinite(max) || max <= 0) return [0, 1];
    const raw = max / count;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const n = raw / mag;
    // 2.5 keeps e.g. a 12.1 Cr max on a 12.5 Cr axis rather than 15 Cr.
    const step = (n >= 5 ? 10 : n >= 2.5 ? 5 : n >= 2 ? 2.5 : n >= 1 ? 2 : 1) * mag;
    const ticks = [];
    for (let v = 0; v <= max + step * 1e-6; v += step) ticks.push(v);
    if (ticks[ticks.length - 1] < max) ticks.push(ticks[ticks.length - 1] + step);
    return ticks;
  }

  const yTicks = $derived(niceTicks(yMaxRaw));
  const yMax = $derived(yTicks[yTicks.length - 1] || 1);

  const sx = $derived((x) =>
    M.left + (xMax === xMin ? 0 : ((x - xMin) / (xMax - xMin)) * plotW)
  );
  const sy = $derived((y) => M.top + plotH - (y / yMax) * plotH);

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

  const endLabels = $derived.by(() => {
    // Stacked tops are running totals; overlapping labels are dropped, not nudged.
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

  let hoverIndex = $state(null);
  let pointerX = $state(0);

  const xValues = $derived(series[0] ? series[0].points.map((p) => p.x) : []);

  function onMove(event) {
    const box = event.currentTarget.getBoundingClientRect();
    const px = event.clientX - box.left;
    pointerX = px;
    if (!xValues.length) return;

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

  const tooltipLeft = $derived(Math.min(Math.max(hoverX, 70), width - 70));
  const tooltipFlip = $derived(hoverX > width * 0.6);
</script>

<div class="chart" bind:clientWidth={width}>
  {#if series.length > 1}
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
    {#each yTicks as t (t)}
      <line x1={M.left} x2={M.left + plotW} y1={sy(t)} y2={sy(t)} class="grid" />
      <text x={M.left - 8} y={sy(t)} class="tick tick-y">{formatY(t)}</text>
    {/each}

    {#each xTicks as t (t)}
      <text x={sx(t)} y={M.top + plotH + 20} class="tick tick-x">{formatX(t)}</text>
    {/each}

    <line
      x1={M.left} x2={M.left + plotW}
      y1={M.top + plotH} y2={M.top + plotH}
      class="axis"
    />

    {#each rules as r (r.label)}
      <line
        x1={M.left} x2={M.left + plotW}
        y1={sy(r.y)} y2={sy(r.y)}
        class="rule" style:stroke={r.color}
      />
      <text x={M.left + 6} y={sy(r.y) - 6} class="rule-label">{r.label}</text>
    {/each}

    {#if stacked}
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

    {#if hoverIndex !== null}
      <line x1={hoverX} x2={hoverX} y1={M.top} y2={M.top + plotH} class="crosshair" />
      {#each drawn as s (s.name)}
        {#if s.points[hoverIndex]}
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

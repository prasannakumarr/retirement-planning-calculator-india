<script>
  let {
    label,
    value,
    note = '',
    tone = 'neutral',
    hero = false,
  } = $props();
</script>

<div class="tile" class:hero>
  <div class="label">{label}</div>
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

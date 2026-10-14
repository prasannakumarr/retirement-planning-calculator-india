<script>
  let {
    label,
    value = $bindable(),
    min = 0,
    max = 100,
    step = 1,
    prefix = '',
    suffix = '',
    hint = '',
    slider = true,
  } = $props();

  const id = $derived(`f-${label.replace(/\W+/g, '-').toLowerCase()}`);

  // An empty box yields '' — coerce so the backend always gets a number.
  function onInput(event) {
    const next = parseFloat(event.currentTarget.value);
    value = isFinite(next) ? next : 0;
  }
</script>

<div class="field">
  <label for={id}>{label}</label>

  <div class="control">
    {#if prefix}<span class="affix">{prefix}</span>{/if}
    <input
      {id}
      type="number"
      {min}
      {step}
      value={value}
      oninput={onInput}
    />
    {#if suffix}<span class="affix suffix">{suffix}</span>{/if}
  </div>

  {#if slider}
    <input
      class="range"
      type="range"
      {min}
      {max}
      {step}
      aria-label="{label} slider"
      value={value}
      oninput={onInput}
    />
  {/if}

  {#if hint}<p class="hint">{hint}</p>{/if}
</div>

<style>
  .field { display: grid; gap: 6px; }

  label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .control {
    display: flex;
    align-items: center;
    gap: 6px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0 10px;
  }
  .control:focus-within { border-color: var(--series-projected); }

  input[type='number'] {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--text-primary);
    font: inherit;
    font-variant-numeric: tabular-nums;
    padding: 9px 0;
    outline: none;
  }

  .affix {
    color: var(--text-muted);
    font-size: 13px;
    flex: none;
  }
  .suffix { white-space: nowrap; }

  .range {
    width: 100%;
    accent-color: var(--series-projected);
    margin: 0;
  }

  .hint {
    margin: 0;
    font-size: 11.5px;
    line-height: 1.45;
    color: var(--text-muted);
  }
</style>

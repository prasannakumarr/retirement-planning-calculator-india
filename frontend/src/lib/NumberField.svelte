<script>
  /*
   * NumberField.svelte — one labelled numeric input, optionally with a slider.
   *
   * WHERE THIS FITS: the building block of InputPanel.svelte. Every question
   * the calculator asks is one of these.
   *
   * The slider is the reason this component exists in this shape. The whole
   * point of the app is to show how the outcome moves when an assumption
   * moves, and dragging a slider while the charts redraw communicates that far
   * better than typing a number and pressing a button. The text box is kept
   * alongside it because sliders are hopeless for entering an exact salary.
   */
  let {
    label,
    value = $bindable(),
    min = 0,
    max = 100,
    step = 1,
    /** Shown before the input, e.g. the rupee sign. */
    prefix = '',
    /** Shown after the input, e.g. '%' or 'years'. */
    suffix = '',
    /** One line under the field explaining what to put in it. */
    hint = '',
    slider = true,
  } = $props();

  // Derived rather than computed once, so the id tracks the label if a parent
  // ever changes it. Used to tie the <label> to its <input> for screen readers.
  const id = $derived(`f-${label.replace(/\W+/g, '-').toLowerCase()}`);

  /*
   * Typing in the box produces a string, and an empty box produces ''. Coerce
   * here so the rest of the app only ever sees a number — sending '' to the
   * backend would come back as a JSON parse error rather than a useful
   * validation message.
   */
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

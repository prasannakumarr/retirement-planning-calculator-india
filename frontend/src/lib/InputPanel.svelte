<script>
  /*
   * InputPanel.svelte — the questions the calculator asks.
   *
   * WHERE THIS FITS: the left-hand column of App.svelte. It owns no state of
   * its own; it binds straight into the `input` object that App holds, and
   * App re-runs the projection whenever anything here changes.
   *
   * The fields are grouped into three sections in order of how confident the
   * user can be about the answer:
   *
   *   1. About you      — facts you know exactly (your age).
   *   2. Your money     — facts you can look up (what you spend, what you have).
   *   3. Assumptions    — guesses about the next thirty years.
   *   4. Tax & health   — finer assumptions, folded away by default. The
   *                       defaults are researched and switched on, so a user
   *                       who never opens the section still gets a realistic
   *                       answer; the summary line on the fold shows what is
   *                       being assumed without opening it.
   *
   * That ordering matters. Putting the assumptions last, visually separated
   * and with their defaults justified in the hints, makes it obvious which
   * numbers are solid and which are the ones to go and argue with. A
   * calculator that presents "11% returns" with the same confidence as "I am
   * 32" is misleading its user.
   */
  import NumberField from './NumberField.svelte';

  let { input = $bindable(), onReset } = $props();

  const taxModes = [
    { value: 'EstimateFromSlabs', label: 'Estimate from slabs' },
    { value: 'FlatRate', label: 'Flat rate' },
    { value: 'NoTax', label: 'Ignore' },
  ];

  // What the folded section is assuming, so it can be read without opening.
  const taxSummary = $derived(
    input.taxMode === 'EstimateFromSlabs'
      ? `Tax from slabs, ${input.equitySharePercent}% equity`
      : input.taxMode === 'FlatRate'
        ? `Tax flat ${input.flatTaxRatePercent}%`
        : 'Tax ignored'
  );
  const healthSummary = $derived(
    `medical ${input.medicalInflationPercent}% tapering, +${input.healthcareAgeingPercent}%/yr ageing`
  );
</script>

<form class="panel" onsubmit={(e) => e.preventDefault()}>
  <!-- One key for every money field below, so no one has to guess whether a
       figure is monthly or yearly, or today's rupees or future ones. -->
  <p class="units-key">
    Enter every amount in <strong>today's rupees</strong> — the calculator does
    the inflating. Each ₹ field says whether it is <strong>a month</strong>,
    <strong>a year</strong> or a <strong>total</strong>.
  </p>

  <section>
    <h2>About you</h2>

    <NumberField
      label="Your age today"
      bind:value={input.currentAge}
      min={18} max={75} suffix="years"
    />

    <NumberField
      label="Age you want to retire"
      bind:value={input.retirementAge}
      min={35} max={80} suffix="years"
      hint="Every extra working year helps twice over: one more year of investing, one fewer year to fund."
    />

    <NumberField
      label="Plan until age"
      bind:value={input.lifeExpectancy}
      min={70} max={100} suffix="years"
      hint="Not a prediction — a planning age. Running out at 85 when you live to 92 is far worse than leaving money behind, so set this generously."
    />
  </section>

  <section>
    <h2>Your money today</h2>

    <NumberField
      label="Household spending, excluding healthcare"
      bind:value={input.currentMonthlyExpense}
      min={5000} max={500000} step={1000} prefix="₹" suffix="a month"
      hint="What you actually spend after tax, not what you earn. Leave healthcare out — it has its own line below, because it rises much faster than everything else."
    />

    <NumberField
      label="Healthcare once retired"
      bind:value={input.healthcareAnnualToday}
      min={0} max={1000000} step={5000} prefix="₹" suffix="a year"
      hint="A yearly figure, unlike the others. Not today's premium: what a year of healthcare will cost once you've retired, priced today. Premiums for your own cover plus what insurance doesn't pay — co-pays, OPD, medicines. A couple's base policy and super top-up run about ₹1 lakh; add ₹50,000 for the rest. Your employer's cover ends when you retire."
    />

    <NumberField
      label="Retirement savings so far"
      bind:value={input.currentCorpus}
      min={0} max={50000000} step={50000} prefix="₹" suffix="total"
      hint="EPF + PPF + NPS + mutual funds + FDs earmarked for retirement. Leave out the home you live in — you cannot spend it."
    />

    <NumberField
      label="Investing for retirement"
      bind:value={input.monthlyInvestment}
      min={0} max={500000} step={1000} prefix="₹" suffix="a month"
      hint="Everything going towards retirement each month, including your EPF contribution."
    />

    <NumberField
      label="Raise that amount each year by"
      bind:value={input.annualStepUpPercent}
      min={0} max={15} step={0.5} suffix="% a year"
      hint="Raising your SIP as your salary grows is the single biggest lever most people have. Default 5% is deliberately below the 10% most calculators assume."
    />

    <NumberField
      label="Other income once retired"
      bind:value={input.otherMonthlyIncome}
      min={0} max={500000} step={1000} prefix="₹" suffix="a month"
      hint="Rent or a pension, per month, in today's money — assumed to rise with inflation, so leave out an EPS pension. Leave at 0 if unsure — that is the safe choice."
    />
  </section>

  <section>
    <h2>Assumptions</h2>
    <p class="section-note">
      These are guesses about the next few decades, not facts. Move them around
      and watch what happens — that is the most useful thing this page does.
    </p>

    <NumberField
      label="Inflation"
      bind:value={input.inflationPercent}
      min={3} max={12} step={0.25} suffix="% a year"
      hint="India's long-run average is around 6%. Healthcare is not included here — it has its own, faster rate under Tax & healthcare."
    />

    <NumberField
      label="Return before retirement"
      bind:value={input.preRetirementReturnPercent}
      min={4} max={18} step={0.25} suffix="% a year"
      hint="Before tax. An equity-heavy portfolio while you still have decades to ride out a crash. 10–12% is the defensible range."
    />

    <NumberField
      label="Return after retirement"
      bind:value={input.postRetirementReturnPercent}
      min={3} max={14} step={0.25} suffix="% a year"
      hint="Before tax — tax on withdrawals is handled separately below. Lower than before retiring, because you are selling units to eat and cannot afford to sell at the bottom."
    />

    <NumberField
      label="Safe withdrawal rate"
      bind:value={input.safeWithdrawalRatePercent}
      min={2.5} max={5} step={0.05} suffix="% a year"
      hint="The American 4% rule does not transfer to India — published Indian studies land at 3–3.5%. At 3.25% you are targeting about 31× your annual expenses."
    />

    <NumberField
      label="Spending change at retirement"
      bind:value={input.expenseAdjustmentPercent}
      min={-40} max={50} step={1} suffix="% of spending"
      hint="Negative if you expect to spend less (no commute, no EMI, children independent); positive if you expect more travel. Healthcare is handled separately."
    />
  </section>

  <details class="fold">
    <summary>
      <span class="fold-title">Tax &amp; healthcare</span>
      <span class="fold-summary">{taxSummary} · {healthSummary}</span>
    </summary>

    <div class="fold-body">
      <div class="field">
        <span class="field-label" id="tax-mode-label">Tax on withdrawals</span>
        <div class="segmented" role="radiogroup" aria-labelledby="tax-mode-label">
          {#each taxModes as m (m.value)}
            <button
              type="button"
              role="radio"
              aria-checked={input.taxMode === m.value}
              class:active={input.taxMode === m.value}
              onclick={() => (input.taxMode = m.value)}
            >
              {m.label}
            </button>
          {/each}
        </div>
        <p class="hint">
          {#if input.taxMode === 'EstimateFromSlabs'}
            Worked out each year from the 2026-27 new-regime slabs. Only the gain
            inside each withdrawal is taxed: 12.5% on equity gains above ₹1.25
            lakh, slab rates on debt gains and on your pension or rent. Assumes
            slabs keep pace with inflation.
          {:else if input.taxMode === 'FlatRate'}
            One rate on every rupee you withdraw. Use this if most of your money
            will sit in FDs or SCSS, whose interest is taxed in full every year.
          {:else}
            Only right if you have already entered after-tax returns above.
            Otherwise this flatters the result.
          {/if}
        </p>
      </div>

      {#if input.taxMode === 'EstimateFromSlabs'}
        <NumberField
          label="Equity share of your retirement corpus"
          bind:value={input.equitySharePercent}
          min={0} max={100} step={5} suffix="% of corpus"
          hint="Equity and debt gains are taxed differently. Debt gains count towards the ₹12 lakh no-tax limit; equity gains don't."
        />
      {:else if input.taxMode === 'FlatRate'}
        <NumberField
          label="Flat tax rate on withdrawals"
          bind:value={input.flatTaxRatePercent}
          min={0} max={30} step={0.5} suffix="% of withdrawals"
          hint="Not your slab rate — the share of what you withdraw that goes in tax. FD-heavy at ₹25 lakh+ a year is about 10–20%; equity SWPs are usually under 8%."
        />
      {/if}

      <NumberField
        label="Medical inflation"
        bind:value={input.medicalInflationPercent}
        min={4} max={15} step={0.5} suffix="% a year, now"
        hint="Insurers' 2026 figures for India are 9.9–12.9%. Those are group-insurance trends and can't last for ever, so this tapers to general inflation + 2 points over 20 years."
      />

      <NumberField
        label="Healthcare cost growth from ageing"
        bind:value={input.healthcareAgeingPercent}
        min={0} max={6} step={0.5} suffix="% a year"
        hint="On top of inflation, from age 60 to 85. Premiums step up 15–25% for every five years of age — roughly 3–5% a year."
      />
    </div>
  </details>

  <button type="button" class="reset" onclick={onReset}>
    Reset to defaults
  </button>
</form>

<style>
  .panel {
    display: grid;
    gap: 26px;
    align-content: start;
  }

  section { display: grid; gap: 16px; min-width: 0; }

  h2 {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border);
  }

  .units-key {
    margin: 0;
    padding: 10px 12px;
    border-radius: 8px;
    background: var(--surface-sunken);
    font-size: 12px;
    line-height: 1.5;
    color: var(--text-secondary);
  }
  .units-key strong { color: var(--text-primary); font-weight: 600; }

  .section-note {
    margin: -6px 0 0;
    font-size: 12px;
    line-height: 1.5;
    color: var(--text-secondary);
  }

  /* ---- the folded Tax & healthcare section ---- */
  .fold {
    border-top: 1px solid var(--border);
    padding-top: 10px;
  }
  .fold summary {
    cursor: pointer;
    display: grid;
    gap: 2px;
    list-style: none;
  }
  .fold summary::-webkit-details-marker { display: none; }
  .fold-title {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
  }
  .fold-title::after { content: ' ▸'; }
  .fold[open] .fold-title::after { content: ' ▾'; }
  .fold-summary {
    font-size: 12px;
    color: var(--text-secondary);
  }
  .fold-body {
    display: grid;
    gap: 16px;
    margin-top: 16px;
  }

  .field { display: grid; gap: 6px; }
  .field-label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
  }
  .hint {
    margin: 0;
    font-size: 11.5px;
    line-height: 1.45;
    color: var(--text-muted);
  }

  .segmented {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    padding: 3px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--surface);
  }
  .segmented button {
    flex: 1 1 auto;
    border: 0;
    border-radius: 6px;
    background: transparent;
    padding: 6px 8px;
    font: inherit;
    font-size: 12.5px;
    color: var(--text-secondary);
    cursor: pointer;
  }
  .segmented button.active {
    background: var(--text-primary);
    color: var(--surface);
  }

  .reset {
    justify-self: start;
    background: transparent;
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 8px 14px;
    font: inherit;
    font-size: 13px;
    color: var(--text-secondary);
    cursor: pointer;
  }
  .reset:hover {
    background: var(--surface-sunken);
    color: var(--text-primary);
  }
</style>

<script>
  import StatTile from './StatTile.svelte';
  import DataTable from './DataTable.svelte';
  import LineChart from './charts/LineChart.svelte';
  import BarChart from './charts/BarChart.svelte';
  import { compactRupees, rupees, percent, ratioAsPercent, signedPercent } from './format.js';

  let { result } = $props();

  const s = $derived(result.summary);

  const toneFor = {
    Comfortable: 'good',
    OnTrack: 'good',
    SlightlyBehind: 'warning',
    Lagging: 'critical',
  };

  const verdictLabel = {
    Comfortable: 'Comfortably ahead',
    OnTrack: 'On track',
    SlightlyBehind: 'Slightly behind',
    Lagging: 'Lagging',
  };

  const tone = $derived(toneFor[s.verdict] ?? 'neutral');

  // A gap that rounds to 0% counts as on target, not −0%.
  const behind = $derived(s.fundedGapPercent < 0 && signedPercent(s.fundedGapPercent) !== '0%');
  const ahead = $derived(s.fundedGapPercent > 0 && signedPercent(s.fundedGapPercent) !== '0%');
  const sipChangePct = $derived(s.monthlyInvestmentChangePercent);

  const growthSeries = $derived([
    {
      name: 'Your projected corpus',
      color: 'var(--series-projected)',
      points: result.accumulation.map((r) => ({ x: r.accAge, y: r.accClosingCorpus })),
    },
    {
      name: 'Where you would be if exactly on track',
      color: 'var(--series-required)',
      points: result.accumulation.map((r) => ({ x: r.accAge, y: r.accTargetCorpus })),
    },
  ]);

  const drawdownSeries = $derived([
    {
      name: 'Corpus remaining',
      color: 'var(--series-projected)',
      area: true,
      points: [
        {
          x: result.echoedInput.retirementAge,
          y: s.projectedCorpusInTodaysRupees,
        },
        ...result.drawdown.map((r) => ({ x: r.drwAge + 1, y: r.drwClosingReal })),
      ],
    },
  ]);

  const comparisonBars = $derived([
    {
      label: 'Need — safe withdrawal method',
      segments: [
        { name: 'Corpus you need', value: s.requiredCorpusSwr, color: 'var(--series-required)' },
      ],
    },
    {
      label: 'Need — depletion method',
      segments: [
        { name: 'Corpus you need', value: s.requiredCorpusDepletion, color: 'var(--series-required)' },
      ],
    },
    {
      label: 'You are on course for',
      segments: [
        { name: 'From savings you already have', value: s.fvOfCurrentCorpus, color: 'var(--series-projected)' },
        { name: 'From future investments', value: s.fvOfFutureInvestments, color: 'var(--series-future)' },
      ],
    },
  ]);

  const needBreakdown = $derived([
    {
      label: 'Corpus you need',
      segments: [
        { name: 'Living costs', value: s.requiredForLiving, color: 'var(--series-living)' },
        { name: 'Healthcare', value: s.requiredForHealthcare, color: 'var(--series-health)' },
        { name: 'Tax', value: s.requiredForTax, color: 'var(--series-tax)' },
      ].filter((seg) => seg.value > 0),
    },
  ]);

  const costSeries = $derived([
    {
      name: 'Living costs',
      color: 'var(--series-living)',
      points: result.drawdown.map((r) => ({ x: r.drwAge, y: r.drwLivingReal })),
    },
    {
      name: 'Healthcare',
      color: 'var(--series-health)',
      points: result.drawdown.map((r) => ({ x: r.drwAge, y: r.drwHealthcareReal })),
    },
    {
      name: 'Tax',
      color: 'var(--series-tax)',
      points: result.drawdown.map((r) => ({ x: r.drwAge, y: r.drwTaxReal })),
    },
  ]);

  const retirementAge = $derived(result.echoedInput.retirementAge);
  const lifeExpectancy = $derived(result.echoedInput.lifeExpectancy);

  const HEALTH_SHARE_WARNING = 60;
</script>

<div class="results">
  <section class="verdict" data-tone={tone}>
    <div class="verdict-head">
      <span class="dot"></span>
      <span class="verdict-label">{verdictLabel[s.verdict] ?? s.verdict}</span>
    </div>
    <div class="hero-number">{ratioAsPercent(s.fundedRatio)}</div>
    <div class="hero-caption">of the corpus you need, by age {retirementAge}</div>

    <div class="gap" data-dir={behind ? 'behind' : ahead ? 'ahead' : 'even'}>
      <div class="gap-figure">
        <span class="gap-pct">{signedPercent(s.fundedGapPercent)}</span>
        <span class="gap-label">
          {behind ? 'behind your target' : ahead ? 'ahead of your target' : 'on target'}
          · {compactRupees(Math.abs(s.surplusOrGap))} {behind ? 'short' : ahead ? 'spare' : ''}
        </span>
      </div>

      {#if behind}
        <p class="gap-action">
          Invest <strong>{rupees(s.monthlyInvestmentChange)} more a month</strong>
          {#if sipChangePct != null}
            — a <strong>{signedPercent(sipChangePct)}</strong> step-up
          {/if}
          — from {rupees(result.echoedInput.monthlyInvestment)} to
          <strong>{rupees(s.requiredMonthlyInvestment)}</strong>, starting now and
          still rising {percent(result.echoedInput.annualStepUpPercent, 1)} a year.
        </p>
      {:else if ahead}
        <p class="gap-action">
          You could invest up to <strong>{rupees(-s.monthlyInvestmentChange)} less a month</strong>
          {#if sipChangePct != null}
            ({signedPercent(sipChangePct)})
          {/if}
          — {rupees(s.requiredMonthlyInvestment)} instead of
          {rupees(result.echoedInput.monthlyInvestment)} — and still reach the target.
          Better to keep the cushion.
        </p>
      {/if}

      {#if behind && sipChangePct != null}
        <p class="gap-why">
          Why {signedPercent(sipChangePct)} and not {signedPercent(-s.fundedGapPercent)}?
          Your savings so far keep growing whatever you do, so only your future
          investments can close the gap — they have to stretch further than the
          gap itself.
        </p>
      {/if}
    </div>

    <p class="verdict-message">{s.verdictMessage}</p>
  </section>

  <div class="tiles">
    <StatTile
      label="Corpus you need at {retirementAge}"
      value={compactRupees(s.requiredCorpus)}
      note="Lump sum, in age-{retirementAge} rupees · {compactRupees(s.requiredCorpusInTodaysRupees)} in today's money · healthcare adds {compactRupees(s.requiredForHealthcare)}, tax {compactRupees(s.requiredForTax)}"
    />
    <StatTile
      label="Corpus you are on course for"
      value={compactRupees(s.projectedCorpus)}
      note="Lump sum, in age-{retirementAge} rupees · {compactRupees(s.projectedCorpusInTodaysRupees)} in today's money"
    />
    <StatTile
      label={s.surplusOrGap >= 0 ? 'Surplus' : 'Shortfall'}
      value={compactRupees(Math.abs(s.surplusOrGap))}
      tone={s.surplusOrGap >= 0 ? 'good' : tone}
      note={s.surplusOrGap >= 0
        ? `Lump sum at ${retirementAge}: how far you are projected to finish ahead of the target.`
        : `Lump sum at ${retirementAge}: how far you are projected to fall short.`}
    />
    <StatTile
      label="Spending at {retirementAge}, per month"
      value="{compactRupees(s.monthlyExpenseAtRetirement)} a month"
      note="What {rupees(result.echoedInput.currentMonthlyExpense)} a month becomes after {s.yearsToRetirement} years of {percent(result.echoedInput.inflationPercent, 1)} inflation — plus {compactRupees(s.healthcareMonthlyAtRetirement)} a month for healthcare ({compactRupees(s.healthcareAtRetirement)} a year)."
    />
  </div>
  <p class="units-note">
    <strong>Future rupees:</strong> corpus figures are one-time lump sums
    priced as they will be at age {retirementAge}, when ₹1 buys far less than
    today. "In today's money" shows what each would buy now.
  </p>

  <section class="action">
    {#if s.additionalMonthlyInvestment > 0}
      <h3>Other ways to close the gap</h3>
      <p>
        Investing an extra {rupees(s.additionalMonthlyInvestment)} a month is not
        the only lever. Retiring two years later, or finding you can live on less
        than you think, both move this number a long way — try them on the left
        and watch the figure at the top shrink.
      </p>
    {:else}
      <h3>You have room</h3>
      <p>
        {rupees(s.requiredMonthlyInvestment)} a month would be enough to hit the
        target, and you are investing {rupees(result.echoedInput.monthlyInvestment)}.
        That spare capacity buys you an earlier retirement, a bigger cushion, or
        a less risky portfolio — not necessarily more spending.
      </p>
    {/if}
  </section>

  <section class="card">
    <h3>What you need, and what you will have</h3>
    <p class="card-note">
      There are two defensible ways to work out what you need, and they
      disagree. The <strong>safe withdrawal</strong> method holds enough that
      drawing {percent(result.echoedInput.safeWithdrawalRatePercent, 2)} a year
      is sustainable indefinitely. The <strong>depletion</strong> method funds
      your expenses exactly and runs the corpus to zero at
      {result.echoedInput.lifeExpectancy}. The second is usually smaller because
      it assumes returns arrive on schedule and you die on time — but it is the
      only one that sees healthcare rising faster than prices, so with large
      healthcare costs it can come out ahead. This page
      targets the larger of the two — currently the
      <strong>{s.requiredCorpusMethod}</strong> figure. All bars are lump sums
      at age {retirementAge}, in that year's rupees.
    </p>
    <BarChart bars={comparisonBars} />
  </section>

  <section class="card">
    <h3>What the corpus you need is made of</h3>
    <p class="card-note">
      Living costs alone would need {compactRupees(s.requiredForLiving)}.
      Healthcare adds <strong>{compactRupees(s.requiredForHealthcare)}</strong>,
      because it rises faster than other prices and faster again as you age.
      Tax on your withdrawals adds <strong>{compactRupees(s.requiredForTax)}</strong>.
      Most calculators leave out both, which is why they tell people to relax
      when they shouldn't.
    </p>
    <BarChart bars={needBreakdown} />
  </section>

  <section class="card">
    <h3>Your corpus between now and retirement</h3>
    <p class="card-note">
      The orange line is where you would be each year if you were exactly on
      track. Watch the two lines separate or converge as you change the
      assumptions on the left. Values are the corpus at each age, in the
      rupees of that year — not today's money.
    </p>
    <LineChart
      series={growthSeries}
      height={300}
      xLabel="Your age"
      formatX={(v) => String(Math.round(v))}
      tooltipTitle={(x) => `Age ${Math.round(x)}`}
    />
  </section>

  <section class="card">
    <h3>Your corpus through retirement, in today's money</h3>
    <p class="card-note">
      {#if s.corpusLastsUntilAge}
        On these numbers the money runs out at age
        <strong>{s.corpusLastsUntilAge}</strong>, which is
        {result.echoedInput.lifeExpectancy - s.corpusLastsUntilAge} years short of
        the age you are planning to.
      {:else}
        The corpus lasts past age {result.echoedInput.lifeExpectancy}, which is
        what you want — the line should still be above zero at the right-hand
        edge.
      {/if}
      This line is in <strong>today's purchasing power</strong>, which is the
      only way to read it honestly. In future rupees the corpus often appears
      to grow right through retirement, because the portfolio earns more than
      you withdraw — but prices climb just as fast, so that apparent growth
      buys you nothing. The table below gives both.
    </p>
    <LineChart
      series={drawdownSeries}
      height={260}
      xLabel="Your age"
      formatX={(v) => String(Math.round(v))}
      tooltipTitle={(x) => `Age ${Math.round(x)}`}
    />
  </section>

  <section class="card">
    <h3>What each year of retirement costs — per year, in today's money</h3>
    <p class="card-note">
      Living costs stay flat in today's money — they rise with prices and no
      faster. Healthcare does not: it goes from
      <strong>{percent(s.healthcareShareAtRetirement, 0)}</strong> of your spending at
      {retirementAge} to <strong>{percent(s.healthcareShareAtEnd, 0)}</strong> by
      {lifeExpectancy}. Tax is the slice on top: on average
      {percent(s.averageTaxRate, 1)} of what you withdraw.
      {#if s.corpusLastsUntilAge}
        These are the costs the plan calls for — after age
        {s.corpusLastsUntilAge} the corpus can no longer pay them.
      {/if}
    </p>
    {#if s.healthcareShareAtEnd > HEALTH_SHARE_WARNING}
      <p class="card-warning" role="note">
        <span class="warn-icon" aria-hidden="true">!</span>
        Healthcare passes {HEALTH_SHARE_WARNING}% of spending by the end. That is
        beyond what Indian data supports — households cut other spending before
        that happens. Consider lowering medical inflation or the ageing rate.
      </p>
    {/if}
    <LineChart
      series={costSeries}
      stacked
      height={260}
      xLabel="Your age"
      formatX={(v) => String(Math.round(v))}
      tooltipTitle={(x) => `Age ${Math.round(x)}`}
    />
  </section>

  <div class="tiles">
    <StatTile
      label="Real return before retirement"
      value={percent(s.realReturnPreRetirement)}
      note="What your money actually gains after inflation. This, not the headline return, is what builds the corpus."
    />
    <StatTile
      label="Real return after retirement"
      value={percent(s.realReturnPostRetirement)}
      note="Often close to zero in India. A corpus that merely keeps pace with prices has to be large enough to be spent down."
    />
    <StatTile
      label="Withdrawal rate this plan implies"
      value={percent(s.impliedWithdrawalRate, 2)}
      tone={s.impliedWithdrawalRate > 3.5 ? 'warning' : 'good'}
      note="Your first year's withdrawal, tax included, as a share of your projected corpus. Above about 3.5% is leaning on optimism."
    />
    <StatTile
      label="Healthcare share of spending"
      value="{percent(s.healthcareShareAtRetirement, 0)} → {percent(s.healthcareShareAtEnd, 0)}"
      note={s.healthcareShareAt75 != null
        ? `At ${retirementAge}, then ${percent(s.healthcareShareAt75, 0)} at 75, and ${percent(s.healthcareShareAtEnd, 0)} at ${lifeExpectancy}.`
        : `At ${retirementAge} and at ${lifeExpectancy}.`}
    />
    <StatTile
      label="Tax on withdrawals"
      value="{percent(s.averageTaxRate, 1)} on average"
      note="{percent(s.firstYearTaxRate, 1)} in the first year, rising as more of each withdrawal is gain rather than money you put in."
    />
    <StatTile
      label="Years funded"
      value="{s.yearsInRetirement} years"
      note="From {retirementAge} to {result.echoedInput.lifeExpectancy}, after {s.yearsToRetirement} years of investing."
    />
  </div>

  <details class="card">
    <summary>Year-by-year numbers</summary>
    <p class="card-note">
      Every row of the first table satisfies opening + invested + growth =
      closing, so you can check any year of the projection by hand.
    </p>
    <DataTable accumulation={result.accumulation} drawdown={result.drawdown} />
  </details>
</div>

<style>
  .results { display: grid; gap: 18px; }

  .verdict {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 22px 24px;
    display: grid;
    gap: 4px;
  }

  .verdict-head {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 600;
  }

  .dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    flex: none;
    background: var(--text-muted);
  }
  .verdict[data-tone='good'] .dot     { background: var(--status-good); }
  .verdict[data-tone='warning'] .dot  { background: var(--status-warning); }
  .verdict[data-tone='serious'] .dot  { background: var(--status-serious); }
  .verdict[data-tone='critical'] .dot { background: var(--status-critical); }

  .verdict[data-tone='good'] .verdict-label     { color: var(--status-good-text); }
  .verdict[data-tone='warning'] .verdict-label  { color: var(--status-warning-text); }
  .verdict[data-tone='critical'] .verdict-label { color: var(--status-critical-text); }

  .hero-number {
    font-size: 52px;
    font-weight: 600;
    line-height: 1.05;
    letter-spacing: -0.02em;
    margin-top: 6px;
  }

  .hero-caption {
    font-size: 13px;
    color: var(--text-secondary);
  }

  .gap {
    margin-top: 12px;
    padding: 12px 14px;
    border-radius: 8px;
    background: var(--surface-sunken);
    display: grid;
    gap: 6px;
  }
  .gap-figure {
    display: flex;
    align-items: baseline;
    flex-wrap: wrap;
    gap: 4px 10px;
  }
  .gap-pct {
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.01em;
  }
  .gap[data-dir='behind'] .gap-pct { color: var(--status-critical-text); }
  .gap[data-dir='ahead'] .gap-pct  { color: var(--status-good-text); }
  .gap-label {
    font-size: 13px;
    color: var(--text-secondary);
  }
  .gap-action {
    margin: 0;
    font-size: 13.5px;
    line-height: 1.55;
    color: var(--text-secondary);
  }
  .gap-action strong { color: var(--text-primary); }
  .gap-why {
    margin: 0;
    font-size: 12px;
    line-height: 1.5;
    color: var(--text-muted);
  }

  .verdict-message {
    margin: 10px 0 0;
    font-size: 13.5px;
    line-height: 1.55;
    color: var(--text-secondary);
    max-width: 62ch;
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
    gap: 12px;
  }

  .card, .action {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 18px 20px;
  }

  h3 {
    font-size: 15px;
    margin-bottom: 6px;
  }

  .card-note, .action p {
    font-size: 12.5px;
    line-height: 1.6;
    color: var(--text-secondary);
    margin: 0 0 14px;
    max-width: 70ch;
  }

  .action p { margin-bottom: 8px; }

  .units-note {
    margin: -6px 0 0;
    font-size: 12px;
    line-height: 1.5;
    color: var(--text-muted);
    max-width: 80ch;
  }
  .units-note strong { color: var(--text-secondary); }

  .card-warning {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    margin: 0 0 14px;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--status-warning-text);
    max-width: 70ch;
  }
  .warn-icon {
    flex: none;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: var(--status-warning);
    color: #0b0b0b;
    font-size: 11px;
    font-weight: 700;
    display: grid;
    place-items: center;
    margin-top: 1px;
  }

  details summary {
    cursor: pointer;
    font-size: 15px;
    font-weight: 600;
    margin-bottom: 10px;
  }
</style>

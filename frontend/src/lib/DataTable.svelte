<script>
  import { rupees, percent } from './format.js';

  let { accumulation = [], drawdown = [] } = $props();

  let tab = $state('accumulation');
</script>

<div class="wrap">
  <div class="tabs" role="tablist">
    <button
      role="tab"
      aria-selected={tab === 'accumulation'}
      class:active={tab === 'accumulation'}
      onclick={() => (tab = 'accumulation')}
    >
      Building the corpus
    </button>
    <button
      role="tab"
      aria-selected={tab === 'drawdown'}
      class:active={tab === 'drawdown'}
      onclick={() => (tab = 'drawdown')}
    >
      Spending it down
    </button>
  </div>

  <p class="units">
    {#if tab === 'accumulation'}
      One row per year. Invested and growth are totals <strong>for the year</strong>;
      opening and closing are the balance. All in the rupees of that year.
    {:else}
      One row per year of retirement. Costs, tax and the withdrawal are totals
      <strong>for the year</strong>, taken at its start. All in the rupees of that
      year, except the last column, which is in today's money.
    {/if}
  </p>

  <div class="scroll">
    {#if tab === 'accumulation'}
      <table>
        <thead>
          <tr>
            <th>Age</th>
            <th>Opening</th>
            <th>Invested in year</th>
            <th>Growth in year</th>
            <th>Closing</th>
            <th>On-track path</th>
          </tr>
        </thead>
        <tbody>
          {#each accumulation as row (row.accYear)}
            <tr>
              <td>{row.accAge}</td>
              <td>{rupees(row.accOpeningCorpus)}</td>
              <td>{rupees(row.accContribution)}</td>
              <td>{rupees(row.accGrowth)}</td>
              <td class="strong">{rupees(row.accClosingCorpus)}</td>
              <td class="muted">{rupees(row.accTargetCorpus)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {:else}
      <table>
        <thead>
          <tr>
            <th>Age</th>
            <th>Opening</th>
            <th>Living costs (year)</th>
            <th>Healthcare (year)</th>
            <th>Tax (year)</th>
            <th>Withdrawn (year)</th>
            <th>Healthcare share</th>
            <th>Growth</th>
            <th>Closing</th>
            <th>Closing (today's money)</th>
          </tr>
        </thead>
        <tbody>
          {#each drawdown as row (row.drwYear)}
            <tr class:empty={row.drwClosingCorpus <= 0}>
              <td>{row.drwAge}</td>
              <td>{rupees(row.drwOpeningCorpus)}</td>
              <td>{rupees(row.drwLivingCost)}</td>
              <td>{rupees(row.drwHealthcareCost)}</td>
              <td>{rupees(row.drwTax)}</td>
              <td>{rupees(row.drwWithdrawal)}</td>
              <td class="muted">{percent(row.drwHealthcareShare, 0)}</td>
              <td>{rupees(row.drwGrowth)}</td>
              <td class="strong">{rupees(row.drwClosingCorpus)}</td>
              <td class="muted">{rupees(row.drwClosingReal)}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  </div>
</div>

<style>
  .wrap { display: grid; gap: 12px; }

  .units {
    margin: 0;
    font-size: 12px;
    line-height: 1.5;
    color: var(--text-muted);
  }
  .units strong { color: var(--text-secondary); }

  .tabs { display: flex; gap: 6px; flex-wrap: wrap; }

  .tabs button {
    background: transparent;
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 5px 13px;
    font: inherit;
    font-size: 12.5px;
    color: var(--text-secondary);
    cursor: pointer;
  }
  .tabs button.active {
    background: var(--text-primary);
    border-color: var(--text-primary);
    color: var(--surface);
  }

  .scroll {
    overflow-x: auto;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    max-height: 420px;
    overflow-y: auto;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12.5px;
    white-space: nowrap;
  }

  th {
    position: sticky;
    top: 0;
    background: var(--surface-sunken);
    text-align: right;
    font-weight: 600;
    color: var(--text-secondary);
    padding: 9px 12px;
    border-bottom: 1px solid var(--border);
  }
  th:first-child, td:first-child { text-align: left; }

  td {
    text-align: right;
    padding: 7px 12px;
    color: var(--text-secondary);
    border-bottom: 1px solid var(--border);
  }
  tbody tr:last-child td { border-bottom: 0; }

  .strong { color: var(--text-primary); font-weight: 600; }
  .muted { color: var(--text-muted); }

  .empty td { opacity: 0.45; }
</style>

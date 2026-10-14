# Assumptions, calculations and caveats

This document explains exactly what the calculator does, why each number was
chosen, and — most importantly — where it is most likely to be wrong. Read the
**Caveats** section before making any decision based on the output.

The calculator targets roughly **±10% accuracy**. That is not a limitation of
the arithmetic, which is exact; it is an honest statement about a model whose
inputs are guesses about the next thirty years.

---

## 1. The model in one paragraph

Retirement planning reduces to comparing two numbers at a single moment in
time — the retirement date:

- **Required corpus** — the lump sum you must have on that date to fund an
  inflating stream of expenses for the rest of your life.
- **Projected corpus** — what your existing savings plus your future monthly
  investments will actually have grown to by then.

Everything the calculator computes serves those two numbers and the gap
between them.

---

## 2. Default parameter values, and why

| Parameter | Default | Justification |
|---|---|---|
| Inflation | **6%** | India's long-run CPI average. The default in HDFC AMC's, Axis Max Life's, ICICI Pru's and Cleartax's calculators. |
| Pre-retirement return | **11%** | Equity-heavy portfolio with decades to ride out a crash. Zerodha Varsity uses 10–11%; Cleartax quotes 8–12%. Deliberately below the 12–15% some calculators advertise. |
| Post-retirement return | **7%** | A debt-heavy but not debt-only portfolio. Matches Axis Max Life's and PrimeInvestor's defaults. The conservative end of the defensible 7–8% range. |
| Retirement age | **60** | The conventional Indian retirement age. |
| Plan-until age | **85** | Used by Axis Max Life, sum.money and honestmoney.in. Note HDFC AMC uses **90**; ICICI Pru's 75 and Groww's 70 are too low and structurally understate the corpus. |
| Safe withdrawal rate | **3.25%** (≈ 31×) | See §4. The American 4% rule does not transfer to India. |
| SIP step-up | **5% a year** | **Deliberately below** the 10% that most Indian calculators assume. See §6. |
| Spending change at retirement | **0%** | Assumes you spend in retirement exactly what you spend now. Neutral by default. |
| Healthcare per year in retirement | **₹1.5 lakh** (today's prices) | A retired couple: about ₹1 lakh of premiums for a base policy plus super top-up, and about ₹50,000 that insurance does not pay (co-pays, OPD, medicines). Entered in rupees because people know their premium, not their spending mix. See §3.9. |
| Medical inflation | **10%**, tapering to inflation + 2 points over 20 years | Aon 11.5%, WTW 12.9%, Mercer 9.9% for 2026 — all employer group-plan trends, which cannot persist for fifty years. See §3.9. |
| Healthcare growth from ageing | **2.5% a year**, age 60–85 | Premiums step up 15–25% per five-year age band (roughly 3–5% a year); IRDAI's 2025 circular asks insurers to consult before raising over-60 premiums by more than 10% a year. The cautious end. |
| Tax on withdrawals | **Estimated from 2026-27 new-regime slabs** | The new regime is the default, chosen by about 88% of filers. Flat-rate and ignore modes are available. See §3.10. |
| Equity share of retirement corpus | **60%** | Only used by the slab estimate, because equity and debt gains are taxed differently. |

### 2.1 Filling in the inputs that are easy to get wrong

**Monthly or yearly?** Spending, investing and other income are **monthly**.
Healthcare is **yearly**. Each field shows "a month" or "a year" beside it.
Every money figure is in **today's rupees** — the calculator does the
inflating.

**Monthly household spending, excluding healthcare.** What you actually spend
after tax, not what you earn. Take premiums, medicines and doctor visits
*out*, or they are counted twice.

**Healthcare per year in retirement.** *Not* the premium you pay today. That
figure is priced for your current age, and if you have employer cover it hides
most of the real cost — that cover ends when you retire. Enter what healthcare
will cost each year **once you are retired, at today's prices**:

1. **Premium.** Get today's quote for someone **your retirement age** (or a
   couple of that age) with the cover you would want — commonly a ₹10–25 lakh
   base policy plus a ₹50 lakh–₹1 crore super top-up. Indicative 2025-26
   figures for ₹10 lakh of cover: about ₹32,000–48,000 a year for one person
   around 61, about ₹41,000–71,000 for a couple; a super top-up adds to this.
2. **Plus what insurance does not pay.** OPD consultations and tests, regular
   medicines, co-pays (often 10–30% of each claim on senior policies),
   room-rent gaps, dental, glasses. ₹30,000–60,000 a year is a reasonable
   allowance; more with a chronic condition.
3. **Enter the total.** Example: ₹1 lakh couple's premium + ₹50,000 out of
   pocket = **₹1,50,000** (the default).

Do not inflate it yourself — medical inflation is applied from today. Do not
average it over retirement either — enter the **first year's** cost; the
ageing factor raises it from 60 to 85. Include parents' premiums if you will
be paying them. This is the input that moves the answer most: on the default
plan ₹1 lakh instead of ₹1.5 lakh takes the target from ₹16.9 Cr to ₹15.1 Cr,
so a real quote is worth five minutes.

**Other income in retirement.** **Monthly**, in today's rupees — ₹20,000 here
means ₹2.4 lakh a year. Assumed to **rise with inflation**, which suits rent
but not an EPS pension (fixed in rupees — leave it out, see §7.2). With tax
estimated from slabs it is taxed **in full** at slab rates; the real 30%
deduction on rent and ₹75,000 standard deduction on a pension are not applied,
so tax here errs slightly high.

---

## 3. The formulas

Notation: `i` = inflation, `r_pre` / `r_post` = nominal returns, `Y` = years to
retirement, `N` = years in retirement.

### 3.1 Expenses at the retirement date

```
Annual expense at retirement = monthly expense today × 12 × (1 + i)^Y
                               × (1 + lifestyle adjustment)
```

Inflation is just compound interest working against you, so this is the same
formula used to grow money.

### 3.2 Real rate of return — the Fisher equation

```
real rate = (1 + nominal) / (1 + inflation) − 1
```

**Not** `nominal − inflation`. At 7% returns and 6% inflation the shortcut
gives 1.0000% and the correct formula gives 0.9434%. The error always runs in
the optimistic direction — it makes money look like it stretches further than
it does — and it grows with the size of the rates.

Working in real terms is what lets the required-corpus calculation ignore
inflation entirely: if withdrawals grow at inflation *and* the corpus grows at
the nominal rate, then in today's-rupee terms the withdrawals are flat. A
growing annuity collapses into a level one.

### 3.3 Required corpus — method 1, depletion

The present value of `N` inflating annual withdrawals, as an **annuity-due**
(the first withdrawal happens on the day you retire, because you need the money
before you can spend it):

```
Corpus = W × [1 − (1 + rr)^−N] / rr × (1 + rr)
```

where `W` is the first year's withdrawal and `rr` is the real rate from §3.2.

This is the formula HDFC AMC publishes, and it is the one most Indian
calculators implement. Two edge cases are handled explicitly:

- **`rr ≈ 0`** (returns exactly matching inflation — an ordinary conservative
  scenario) would divide by zero. The limit is `Corpus = W × N`.
- **`rr < 0`** (returns below inflation) is handled by the same formula and
  correctly demands *more* than `W × N`.

### 3.4 Required corpus — method 2, safe withdrawal rate

```
Corpus = W / SWR
```

At the 3.25% default this is about 31× the first year's expenses.

### 3.5 Which one the calculator reports

**The larger of the two.** See §4 for why this matters so much.

### 3.6 Projected corpus

Existing savings compound on their own:

```
FV of current corpus = corpus × (1 + r_pre)^Y
```

Future investments are rolled forward a year at a time:

```
closing(k) = closing(k−1) × (1 + r_pre) + FV of year k's twelve SIPs
monthly(k) = monthly(1) × (1 + step-up)^(k−1)
```

The twelve monthly instalments inside each year are compounded at a **monthly**
rate as an annuity-due (SIPs are debited on the 1st, so the money starts
working immediately):

```
monthly rate = (1 + r_pre)^(1/12) − 1
FV of one year = monthly × [(1+m)^12 − 1] / m × (1 + m)
```

At 11% a year, ₹1 invested monthly becomes **₹12.70** by year end, not ₹12.
Ignoring that intra-year growth understates the final corpus by several percent
over a long horizon.

### 3.7 Required monthly investment

The accumulation is **linear** in the monthly amount, so this is solved in
closed form rather than by searching:

```
required monthly = (required corpus − FV of existing corpus) / FV per ₹1 of SIP
```

floored at zero. With slab tax this is iterated to a fixed point (§3.8),
because a bigger SIP changes how much of the corpus is gain and so moves the
target.

### 3.7a How far behind or ahead — and what it means per month

Directly under the headline percentage the page shows three figures, all
computed in the backend:

```
gap                    = (projected / required − 1) × 100        e.g. −28%
monthly change         = required monthly − monthly invested now  e.g. +₹15,271
monthly change as %    = monthly change / monthly invested now    e.g. +51%
```

A negative gap means **behind**: invest the monthly change *extra*, starting
now and still rising at the step-up rate. A positive gap means **ahead**: the
target would still be hit investing that much *less* (the page advises keeping
the cushion). The percentage is omitted when nothing is invested today.

**Being 28% short does not mean investing 28% more.** On the default plan the
answer is +51%. Savings already held keep compounding whatever you do, so only
future investments can close the gap — they must cover all of it on their own.
The further along you are, the bigger the step-up a given gap demands.

Checked on the default plan (target needs ₹45,271 a month):

| Invested now | Gap | Monthly change |
|---|---|---|
| ₹30,000 | −28% | +₹15,271 (+51%) |
| ₹40,000 | −10% | +₹5,271 (+13%) |
| ₹60,000 | +27% | −₹14,729 (−25%) |
| ₹1,00,000 | +101% | −₹54,729 (−55%) |

A self-check proves that today's SIP plus the stated change lands exactly on
the target, in both directions.

### 3.8 Drawdown

Each retirement year: work out what the year costs (living costs + healthcare,
less other income), gross it up for tax, withdraw that at the start, then let
the remainder grow. The withdrawal is capped at the available balance and the
closing balance is floored at zero, so a failing plan flattens along the axis
rather than plunging into meaningless negative territory. The first year the
cap bites is reported as "the corpus runs out at age X".

Alongside the balance the engine tracks its **cost basis** — the rupees
originally put in. Growth adds to the balance but not the basis; each
withdrawal removes basis in proportion (average cost). So the **gain
fraction** of each withdrawal, `1 − basis / balance`, rises through
retirement, and with it the tax.

With healthcare and tax switched on, withdrawals no longer grow at exactly
inflation, so the depletion corpus (§3.3) is computed as the present value of
the year-by-year withdrawals rather than the closed-form annuity. With slab
tax, each year's tax depends on the gain fraction, which depends on the
corpus, so the depletion corpus is found by bisection on the simulated end
balance. A self-check proves that with healthcare at zero and tax off, the
new engine reproduces the closed-form annuity exactly.

The required monthly investment (§3.7) is likewise solved as a fixed point:
investing more changes how much of the final corpus is gain, which moves the
tax and so the target.

### 3.9 Healthcare

Healthcare is a separate cost stream, entered as a yearly figure in today's
prices, and grown from **today** — not from the retirement date:

```
healthcare(year) = H₀ × Π(1 + m(s)) × ageing(age)

m(s)        = m₀ + (m∞ − m₀) × min(s, 20) / 20     m₀ = 10%, m∞ = inflation + 2 points
ageing(age) = 1.025 ^ (clamp(age, 60, 85) − clamp(retirementAge, 60, 85))
```

**Why it tapers.** The 10–13% figures quoted for India are employer
group-insurance cost trends. They bundle price rises with people using more
care and insurers repricing after losses — and forecasts run high (WTW
forecast 13.2% for 2025; the actual was 11.4%). India's CPI health index has
run only about half a point above headline CPI over the last decade. Held at
11.5% for fifty years, healthcare becomes 70% of an 85-year-old's spending,
which no data supports. Actuarial long-run models (the US Society of
Actuaries' Getzen model) assume medical trend converges towards income growth
for the same reason. If the near-term rate is set below the long-run target it
is held flat rather than tapering upwards.

**Why ageing is separate.** Trend rates are measured on an insured population
whose average age does not change, so they leave out an individual getting
older. Premium age bands rise 15–25% per five years. The factor stops at 85,
beyond which the data runs out.

**What falls out.** On the default scenario healthcare is about **30%** of
spending at 60, **45%** at 75 and **55%** at 85 — consistent with older-only
Indian households spending several times as much per head on health as other
households. The page warns if the share passes 60%.

**Why a figure for retirement, not today.** While working, an employer's group
policy hides most of the cost. It ends on the last day of work. So the main
spending input now *excludes* healthcare, and healthcare is asked for as what
it will cost once retired.

### 3.10 Tax on withdrawals

Three modes:

- **Estimate from slabs** (default). Each year, in today's rupees against
  today's slabs:
  - equity gains `= e × W × g` are taxed at **12.5% above ₹1.25 lakh**, after
    setting off any basic exemption (₹4 lakh) that normal income left unused;
  - debt gains `= (1 − e) × W × g` plus other income (pension, rent) are taxed
    at **new-regime slab rates** — nil to ₹4 lakh, then 5% steps per ₹4 lakh to
    30% above ₹24 lakh — with **no tax at or below ₹12 lakh** of normal income
    (section 87A) and marginal relief just above it. The rebate does not reach
    equity gains (Finance Act 2025);
  - surcharge above ₹50 lakh (capped at 15% on equity gains), then 4% cess.

  The gross withdrawal solves `W = max(0, spending + tax(W) − other income)`
  by iteration, since tax depends on the withdrawal. Spending and tax are
  netted against other income *together*, then floored at zero — so a pension
  or rent larger than spending pays its own tax, and the corpus funds only
  whatever tax the surplus cannot cover. (An earlier version floored
  `spending − other income` first, discarding the surplus and then charging
  the income's tax to the corpus: a ₹24 lakh pension against ₹7.2 lakh of
  spending demanded a ₹5.6 Cr corpus instead of none. Two self-checks now
  guard this.) At the defaults this comes to about **4% of the
  withdrawal in year one and 6% on average** over retirement.
- **Flat rate.** `W = need / (1 − t)`. For FD- or SCSS-heavy retirees, whose
  interest is taxed in full every year, or anyone who prefers a round number.
- **Ignore.** Only right if the return assumptions entered are already after
  tax. Otherwise it double-flatters the result.

The gain fraction at retirement comes from the projection itself: everything
invested (plus today's savings, counted as all principal because their history
is unknown) divided by the projected corpus. On the default plan about 81% of
the corpus at 60 is gain.

**Slabs are assumed to keep pace with inflation.** They are not indexed by
law; they are revised ad hoc (Budgets 2023 and 2025 both raised them). If
they froze in rupee terms, tax would creep up over a thirty-year retirement.

---

## 4. The most important thing on this page: the two methods disagree

For typical Indian inputs the **safe withdrawal** method asks for **30–50%
more** than the **depletion** method. With the research reference case
(₹50,000/month today, age 30→60, 25 years of retirement, 6% inflation, 8%
post-retirement return):

| Method | Required corpus |
|---|---|
| Depletion (runs to zero at 85) | **₹6.95 Cr** |
| 30× annual expenses (≈3.33% SWR) | **₹10.34 Cr** |

They are not answering the same question. The depletion method assumes returns
arrive **exactly on schedule** and that you die **exactly on time**. The SWR
method implicitly buys insurance against both — against a bad first decade of
markets (sequence-of-returns risk) and against living longer than planned.

**Most Indian calculators show only the depletion number.** This one shows both
and headlines the larger, because the two errors are wildly asymmetric:
over-saving means retiring with money left over, while under-saving means
running out at 80 with no way back into the workforce.

### Why 3.25% and not 4%

The American 4% rule rests on US market history and does not transfer:

- **Saraogi (2024), "Balancing Acts: Safe Withdrawal Rates in the Indian
  Context"** — applies Bengen's methodology to Indian data and finds **3.0%**
  sustainable for the average Indian investor, **2.6%** for conservative ones.
- **Basunivesh's Monte Carlo** (50:50 Nifty TRI / 10-yr G-Sec, 6% inflation,
  30-year horizon) — **3.5% survives 89.9%** of simulated paths; **4.0%
  survives only 77.7%**. A 22% failure rate is not acceptable for an outcome
  you cannot retake.
- A **2025 follow-up paper** (Indian data 1992–2024) finds the SWR is
  tax-bracket dependent: **3.5–4.2%** below the ₹12 lakh threshold but
  **2.7–3.2%** for 30%-bracket retirees. Taxes are the single biggest factor.
- Indian FIRE communities correspondingly target **30×–40×** annual expenses
  rather than the Western 25×.

One dissenting voice: the **FI India community wiki** argues the 4% rule
"remains valid even for India" — while conceding that 3% (33×) is safer and
that early retirement needs "more than 25×".

---

## 5. Verified against independent calculations

The backend runs **11 self-checks at start-up and refuses to serve if any
fail**. A calculator that is wrong is worse than one that does not run.

Checks include:

1. Compound interest: ₹1,00,000 at 10% for 10 years = ₹2,59,374.
2. The real rate uses Fisher, not subtraction (0.9434%, not 1%).
3. One year of ₹1 monthly SIP at 11% is worth ₹12.70, not ₹12.
4. Zero real return ⇒ corpus is exactly `N` years of expenses.
5. The depletion corpus lands in the familiar 18–32× band.
6. The SWR corpus is exactly the reciprocal of the withdrawal rate.
7. The headline requirement is the larger of the two methods.
8. **Matches an independently computed reference case to within 0.5%** —
   ₹6.9469 Cr required and ₹2.9960 Cr FV of existing corpus, both derived
   outside the program during research.
9. **Spending the depletion corpus leaves it exhausted exactly at the planning
   age** — the strongest internal check available. Too much left over means the
   formula over-saves; a premature zero means it under-saves.
10. Investing the prescribed monthly amount hits the required corpus exactly.
11. A plainly under-saved plan is reported as lagging and runs out early.

Additionally, every row of the accumulation table satisfies
`opening + invested + growth = closing`, so any year can be checked by hand.

---

## 6. Deliberate divergences from popular Indian calculators

These are choices, not bugs. Each one errs on the conservative side.

| Choice | Most calculators | This one | Why |
|---|---|---|---|
| Monthly rate from an annual return | `r / 12` | `(1+r)^(1/12) − 1` | Mutual fund returns are quoted as CAGR, an *effective* annual figure. Dividing by 12 treats 12% as a nominal rate compounded monthly, quietly inflating it to an effective 12.68%. Our SIP figures land ~3–4% below Groww's as a result. |
| Required corpus | Depletion only | **max(depletion, SWR)** | See §4. |
| SIP step-up default | 10% | **5%** | A step-up that is too high flatters the result over 30 years. The bias throughout is towards under-promising. |
| Drawdown chart | Nominal rupees | **Today's rupees** | Whenever returns beat the withdrawal rate the nominal corpus *grows* through retirement, which looks like getting richer and is nothing of the sort. In today's purchasing power the same plan shows a steady drawdown. |
| Withdrawal timing | Varies | Annuity-**due** | You need the year's money before you can spend it. |
| SIP timing | Varies | Annuity-**due** | A SIP mandate debits on the 1st; units are allotted immediately. |

One formula seen in the wild and **deliberately not used**: the growing
perpetuity `Corpus = Annual expense / (r_post − i)`. Axis Max Life publishes
it. With their own defaults (7% and 6%) the denominator is 1%, giving roughly
**2.6× the finite-horizon answer**; it explodes as `r_post → i` and goes
negative when `r_post < i`.

---

## 7. Caveats — read this before trusting any number

### 7.1 What the model leaves out entirely

- **Tax detail the slab estimate skips** (see §3.10 for what it covers). The
  old regime and its senior-citizen extras; FD/SCSS interest being taxed
  yearly rather than on redemption (use the flat-rate mode); first-in-first-out
  redemption, which taxes slightly more early on than the average-cost basis
  used here; the ₹75,000 standard deduction on a pension and the 30% deduction
  on rent (both left out, so tax errs high); surcharge marginal relief; tax
  during the accumulation years (returns before retirement are pre-tax).
- **Healthcare is a smooth trend.** Real healthcare spending is lumpy — a
  hospitalisation, a cancer, long-term care — and the model spreads it as a
  rising average.
- **Sequence-of-returns risk.** Returns are assumed to arrive smoothly at the
  same rate every year. Real markets deliver them lumpily, and a bad first
  decade of retirement does disproportionate damage. The SWR method (§4) is
  the only defence here, which is why it headlines.
- **A separate medical emergency buffer.** Some Indian planners hold ₹50 lakh
  outside the retirement corpus for this. Not modelled.
- **NPS's 40% mandatory annuitisation.** Only 60% of an NPS corpus is freely
  withdrawable. If a large share of your savings is NPS, your usable corpus is
  smaller than the figure you entered.
- **Instrument-specific returns.** EPF (8.25% FY 2025-26), PPF (7.1%) and NPS
  (~10–12%) all compound differently, but the calculator applies one blended
  pre-retirement rate to everything.
- **One-off future costs** — children's education, weddings, a house purchase —
  which can consume a large slice of the corpus being projected here.
- **Your home.** Correctly excluded: you cannot spend the house you live in.

### 7.2 Structural limitations

- **Annual granularity.** The model steps a year at a time (with a monthly
  inner loop for SIPs). Month-level precision would change answers by well
  under 1%.
- **Whole years only.** Ages are rounded to whole years.
- **A single, constant return.** No volatility, no glide path from equity to
  debt as retirement approaches.
- **Two inflation rates, not many.** Living costs inflate at one rate,
  healthcare at another; education, travel and the rest are not separated.
- **"Other income" is assumed inflation-linked.** True for rent; **false for an
  EPS pension**, which is fixed in nominal terms and loses roughly half its
  purchasing power over 12 years at 6% inflation. Do not enter an EPS pension
  here.

### 7.3 How to use it responsibly

1. **Treat the output as a range, not a number.** ±10% is the honest claim; on
   a thirty-year horizon the true uncertainty is wider still.
2. **Vary the assumptions.** The most valuable thing this page does is show how
   much the answer moves. If a 1% change in the return assumption changes your
   verdict, the verdict was never solid.
3. **Stress-test it.** Try inflation at 8%, pre-retirement returns at 9%,
   planning to 90. If the plan survives all three at once, it is robust.
4. **Re-run it annually.** A thirty-year projection made once and filed away is
   worthless; the point is the course correction.
5. **It is not financial advice.** A rough tax estimate, no product selection, no personal
   circumstances. For a real plan, talk to a SEBI-registered investment adviser.

---

## 8. Possible refinements, roughly in order of value

> **Tax and a separate healthcare stream are now built** — see §3.9 and §3.10.
> On the default scenario they raise the required corpus from ₹11.3 Cr to
> ₹16.9 Cr (+49%), and move the verdict from *on track* to *lagging*.

1. **A slabs-frozen option** for tax, to show bracket creep.
2. **A medical emergency reserve** held outside the corpus.
3. **Monte Carlo simulation** instead of a single smooth return, reporting a
   success probability rather than one number.
4. **Separate EPF / PPF / NPS buckets** at their own rates, with NPS's 60%
   usable fraction applied.
5. **A glide path** shifting equity to debt as retirement approaches.
6. **One-off goals** (education, weddings) as dated withdrawals.
7. **Couples** — joint life expectancy, two income streams, survivor spending.
8. **An EPS pension input** that is correctly *not* inflation-linked.

---

## 9. Sources

**Methodology and formulas**
- [HDFC AMC Retirement Calculator](https://www.hdfcfund.com/calculators/retirement-calculator) — publishes the real-rate annuity formula explicitly; the model this implementation follows
- [Cleartax Retirement Planning Calculator](https://cleartax.in/s/retirement-planning-calculator)
- [Zerodha Varsity — The Retirement Problem](https://zerodha.com/varsity/chapter/the-retirement-problem-part-1/)
- [sum.money India Retirement Calculator](https://sum.money/in/retirement-calculator/) — clearest published write-up of the three-step formula set
- [Axis Max Life Retirement Calculator](https://www.axismaxlife.com/insurance-calculators/retirement-planning-calculator) — sensible defaults, but publishes the perpetuity formula
- [PrimeInvestor Retirement Calculator](https://primeinvestor.in/calculators/retirement-calculator/)

**Safe withdrawal rates for India**
- [Saraogi, "Balancing Acts: Safe Withdrawal Rates in the Indian Context"](https://www.researchgate.net/publication/377989042_Balancing_Acts_Safe_Withdrawal_Rates_in_the_Indian_Context)
- [Basunivesh — Safe Withdrawal Rate India: is 3.5% better than 4%?](https://www.basunivesh.com/safe-withdrawal-rate-india/)
- [VRID summary of the 2025 India SWR paper](https://blog.vrid.in/2025/11/11/indias-safe-withdrawal-rate-what-the-new-research-says/)
- [FI India community wiki — SWR strategy](https://fiindia.gitbook.io/wiki/how-much-do-i-need/fire-portfolio/the-safe-withdrawal-rate-swr-strategy)
- [freefincal — Beware of incorrect assumptions while planning for FIRE](https://freefincal.com/early-retirement-incorrect-assumptions/)
- [honestmoney.in — How much do you need to retire in India](https://honestmoney.in/epf-retirement/how-much-need-retire-india-real-number/)

**Rates and inflation**
- [WTW 2026 Global Medical Trends Survey](https://www.wtwco.com/en-cm/insights/2025/10/2026-global-medical-trends-survey)
- [Milliman — Measuring medical inflation in India](https://www.milliman.com/en/insight/measuring-medical-inflation-in-india)
- [Society of Actuaries — 2026 Getzen model update](https://www.soa.org/resources/research-reports/2025/2026-getzen-model-update/)
- [ValueResearch — IRDAI caps senior premium hikes at 10%](https://www.valueresearchonline.com/stories/222990/senior-citizens-insurance-premium-hike-limited-to-10-per-cent-by-insurers-says-irdai/)
- [PolicyX — how premiums rise with age](https://www.policyx.com/health-insurance/articles/health-insurance-premiums-rise-with-age/)
- [Pandey et al., WHO Bulletin 2018 — health spending of older Indian households](https://pmc.ncbi.nlm.nih.gov/articles/PMC5791868)
- [Income Tax Department — FAQs on transition to the Income-tax Act 2025](https://www.incometaxindia.gov.in/documents/81799/11848482/FAQs-on-Interplay-and-Transition.pdf/05f80c1a-073c-a5d7-fb6f-55509242be53?t=1774082865717)
- [Cleartax — income tax changes from April 2026](https://cleartax.in/s/income-tax-changes-from-april-2026)
- [Upstox — LTCG on an SWP and the basic exemption](https://upstox.com/news/personal-finance/investing/i-am-living-on-a-mutual-fund-swp-after-retirement-how-will-my-5-lakh-ltcg-be-taxed/article-166541/)
- [TaxGuru — section 87A and special-rate income](https://taxguru.in/income-tax/rebate-u-s-87a-applicability-stcg-u-s-111a-filing-itr.html)
- [freefincal — how to include tax in retirement planning](https://freefincal.com/how-should-i-include-tax-while-planning-for-retirement/)
- [Aon: India's 2026 medical trend rate is 11.5%](https://www.aon.com/apac/in-the-press/asia-newsroom/2025/india-outpaces-global-average-with-2026-medical-trend-at-11-5-percent-aon-reports)
- [Cleartax — EPF interest rate 8.25% FY 2025-26](https://cleartax.in/s/epf-interest-rate)
- [Business Standard — small savings rates Jan–Mar 2026 (PPF 7.1%, SCSS 8.2%)](https://www.business-standard.com/amp/finance/personal-finance/ppf-nsc-scss-and-more-small-savings-rates-for-january-march-2026-126010700596_1.html)
- [HDFC Securities — latest NPS returns](https://www.hdfcsec.com/latest-returns-nps)

**Sources deliberately not calibrated against**
- Groww's retirement calculator illustration uses 3% inflation, 7% returns and
  a life expectancy of 70. Every one of those is wrong for India.
- ICICI Pru defaults to a life expectancy of 75; FundsIndia models only a
  20-year retirement.
- sum.money's worked example does not reconcile: its stated inputs imply
  ₹6.8–6.9 Cr, but it reports ₹5.38 Cr — consistent with a ~19-year retirement
  rather than the 25 it states.

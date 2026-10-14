# Proposed improvements

**Status:** changes 1 and 2 **built** (10 Oct 2026), revised after research —
see below. Change 3 (the rename) not yet built.

> **What changed from this design when it was built.** Research against 2026
> sources revised three things. (1) Healthcare is entered in **rupees per year
> in retirement** (default ₹1.5 lakh), not as a share of today's spending — an
> employer policy hides the true cost while working. (2) Medical inflation
> **tapers** from 10% to inflation + 2 points over 20 years, plus a separate
> **2.5%/yr ageing factor** from 60 to 85; a flat 11.5% made healthcare 69% of
> spending by 85. (3) Tax is **estimated from the 2026-27 new-regime slabs** on
> the gain portion of each withdrawal, with flat-rate and ignore modes; a flat
> 8% was too high for small drawdowns and too low for large SIP-built ones.
> Result on the default scenario: required corpus ₹11.3 Cr → ₹16.9 Cr (+49%).
> The as-built logic is documented in `ASSUMPTIONS.md` §3.8–3.10. Parts 2–3
> below are the original design, kept for the reasoning.
**Companion to:** [`ASSUMPTIONS.md`](./ASSUMPTIONS.md), which documents what the
calculator does *today*. This file is about what comes next.

## Three changes, in the order they should ship

| # | Change | Size | Why |
|---|---|---|---|
| **3** | **Rename "safe withdrawal rate" → "safe income rate"**, and show the multiple beside it | ~15 min, UI only | The current label actively misleads. Cheapest win in the file — do it first. |
| **1** | **Split healthcare into its own inflation stream** | ~1 hr | Biggest single correction: **+45%** on required corpus |
| **2** | **Tax on withdrawals** | ~20 min | **+8.7%**, and the research says it is the largest omission |

Changes 1 and 2 fix the same class of defect: a **systematic bias that always
runs in one direction**. Everything the calculator currently leaves out makes
your position look *better* than it is, so it is flattering every user who opens
it. Together they raise the required corpus by roughly **58%**.

Change 3 fixes nothing numerical — it fixes the *explanation*, which turned out
to be where people actually get stuck.

## How to read this file

- **Part 1** explains all three concepts in plain terms. This is teaching
  material; much of it should end up in UI hints.
- **Part 2** quantifies changes 1 and 2.
- **Part 3** is the implementation plan for changes 1 and 2.
- **Part 4** is the implementation plan for change 3.

---

# Part 1 — The concepts

## 1.1 What a "safe withdrawal rate" actually is

### The basic problem

You retire with a pot of money. You will never earn a salary again. Every year
for the rest of your life you take money out of that pot to live on, and
whatever is left keeps earning returns.

One question matters: **how much can you take out each year without the pot
running dry before you die?**

- Take too much → broke at 80, with no way back into the workforce.
- Take too little → you die rich, having spent 25 years being needlessly frugal.

The safe withdrawal rate is the answer, expressed as a percentage of the
**starting** pot.

> "3.25% is safe" means: in your first year of retirement, take out 3.25% of the
> pot. After that, raise that **rupee amount** by inflation each year and keep
> taking it. Do that and the money should outlast you.

You set the percentage **once**, on day one. After that you are not
recalculating a percentage — you are paying yourself a fixed, inflation-adjusted
salary.

### Why you can't just withdraw the return

If the portfolio earns 7%, why not take 7%?

**Reason one — inflation takes most of it.** Earn 7%, lose 6% to rising prices,
and the real gain is about 1%. Take 7% out and you are eating the pot itself.

**Reason two — and this is the one nobody expects.** The order in which returns
arrive changes the outcome, even when the returns themselves are identical.

### The demonstration

The same ten yearly returns, in two different orders:

```
  good years first:  +30% +25% +20% +15% +10%  -5% -10% -15% -20% -25%
  bad  years first:  -25% -20% -15% -10%  -5% +10% +15% +20% +25% +30%
```

Starting pot ₹1 crore in both cases.

**Case 1 — still working, withdrawing nothing:**

| | Ends at |
|---|---|
| good years first | ₹1.0756 Cr |
| bad years first | ₹1.0756 Cr |

**Identical.** Multiplication does not care about order.

**Case 2 — retired, withdrawing ₹8 lakh every year:**

| Year | Good-first | Bad-first |
|---:|---:|---:|
| 1 | ₹1.20 Cr | ₹0.69 Cr |
| 2 | ₹1.40 Cr | ₹0.49 Cr |
| 3 | ₹1.58 Cr | ₹0.35 Cr |
| 4 | ₹1.72 Cr | ₹0.24 Cr |
| 5 | ₹1.81 Cr | ₹0.15 Cr |
| 6 | ₹1.64 Cr | ₹0.08 Cr |
| 7 | ₹1.40 Cr | **₹0.00 Cr — broke** |
| 8 | ₹1.13 Cr | ₹0.00 Cr |
| 9 | ₹0.84 Cr | ₹0.00 Cr |
| 10 | ₹0.57 Cr | ₹0.00 Cr |

Same returns. Same withdrawals. One finishes with ₹57 lakh; the other is broke
in year 7 — despite the bad-first retiree's last five years being the five best
years in the set.

### Why the order matters once you are withdrawing

When the market falls and you are **not** withdrawing, you simply wait. Your
units are still there, and they recover with the market.

When the market falls and you **are** withdrawing, you must sell units at the
bottom to eat. **Those units are gone forever.** They are not there to
participate in the recovery. The pot is permanently smaller, and you spend the
rest of retirement drawing from a stump.

That is why the bad-first retiree never recovers. By the time the good years
arrived, there was almost nothing left to act on.

This is called **sequence-of-returns risk**, and it is the single most important
idea in retirement planning that accumulation-phase thinking does not prepare
you for.

### So what "safe" means

You do not get to choose your order. You retire on a date and the market hands
you whatever sequence it hands you. You might retire in 2008. You find out
afterwards.

So a safe withdrawal rate is **not** "what works on average". It is:

> **The rate low enough that you survive even if a bad decade lands right at the
> start of your retirement.**

Deliberately pessimistic, because this is a decision you make exactly once.

### Why 3.25% for India

Researchers test a candidate rate against thousands of possible market
sequences and count how often it lasts 30 years. For India:

| Rate | Survived |
|---|---|
| 3.5% | ~90% of simulated paths |
| 4.0% | ~78% of simulated paths |

A 22% failure rate is unacceptable for something you cannot retake. Indian
research lands at **3–3.5%**, below the American 4%, because Indian inflation is
higher and the data more volatile.

### Why a LOWER rate means you need a BIGGER corpus

This trips everyone up. The thing to hold fixed is **your spending** — it is not
a choice, it is what your life costs. The rate does not change what you spend.
It changes **how big a pot that spending must come out of.**

Using a worked example where the retiree needs ₹34,59,458 a year:

| Safe rate | Your ₹34.6 L is… | So the pot must be |
|---|---|---|
| 5.00% | 5% of the pot | ₹6.92 Cr (20×) |
| 4.00% | 4% of the pot | ₹8.65 Cr (25×) |
| 3.50% | 3.5% of the pot | ₹9.88 Cr (28.6×) |
| 3.25% | 3.25% of the pot | ₹10.64 Cr (30.8×) |
| 3.00% | 3% of the pot | ₹11.53 Cr (33.3×) |
| 2.50% | 2.5% of the pot | ₹13.84 Cr (40×) |

Same ₹34.6 lakh in every row. Only the denominator moves.

The trap is reading "lower withdrawal rate" as "I withdraw less money". You do
not. You withdraw the **same rupees** — they are just a smaller *slice* of a
bigger pie.

> **Analogy.** A fruit tree you can never cut into. If it safely yields 4% of
> itself per year and you need 30 kg of fruit, a 750 kg tree feeds you. In a
> harsher climate where it only safely yields 3%, you need a **1000 kg** tree for
> the same 30 kg. A lower safe yield is bad news — your capital is less
> productive and more fragile — so you need more of it.

---

## 1.2 Medical inflation — and the thing it is *not*

### Two separate effects that get confused

Observed example: a 40-year-old pays **₹16,000/year** for health cover; their
father at 65 pays **₹45,000/year**.

That 2.8× gap is **not medical inflation**. Both figures are in *today's*
rupees. It is **age pricing** — the insurer charging more for an older body,
right now.

Medical inflation is the *separate* thing that happens to the whole price list
over time. Both apply, and they **multiply**:

```
  ₹16,000/yr  ──×2.8 (you age 40→65)──►  ₹45,000  (today's 65-yr-old rate)
                                            │
                                            ├──×4.3 at 6% general inflation
                                            │        →  ₹1,93,000/yr
                                            │
                                            └──×15.2 at 11.5% medical trend
                                                     →  ₹6,84,000/yr   ◄── reality
```

So the ₹45,000 the father pays today is **not** what the son will pay at 65. On
these assumptions it is about **₹6.84 lakh a year** — roughly **43×** the
current premium, of which only 2.8× is ageing and **15.2× is inflation**.

As a share of spending, the premium **alone** goes from **1.4% today to about
13.9% at 65**.

### Why this breaks the model's arithmetic, not just its numbers

The decisive fact:

```
  general spending   7% return vs  6.0% inflation  →  real return  +0.94%
  healthcare         7% return vs 11.5% inflation  →  real return  −4.04%
```

A **negative real return** is a different mathematical regime. The annuity
formula does not just ask for a bit more — it asks for dramatically more,
because the capital funding that stream loses purchasing power every single
year no matter how well it is invested.

### The share rises on its own

Model healthcare as a separate stream and one thing falls out for free, without
being assumed:

> **15% of spending today becomes 31.6% of spending by retirement** (over 19
> years, 11.5% vs 6%).

The model would automatically reproduce what actually happens to retirees —
healthcare quietly eating the budget — rather than needing it hard-coded.

### Having insurance does not remove the problem

Cover reduces the medical bucket; it does not zero it. Indian policies leave
outside:

- **Room-rent caps and sub-limits** — you pay the difference
- **Co-pays**, mandatory on many senior-citizen policies
- **Outpatient everything** — consultations, diagnostics, chronic medication
- **Dental, vision, hearing aids, physiotherapy**
- **Long-term and home care**, essentially uncovered in India

For many retirees the out-of-pocket share exceeds the premium. The parameter
must mean **premium + everything insurance does not pay**. Setting it to zero
because you hold a policy is the mistake — the policy is itself the thing
inflating at 11.5%.

### Source

**Aon 2026 Global Medical Trend Rates Report: India = 11.5%** for 2026 (down
from 13.0% projected for 2025; global average 9.8%).
<https://www.aon.com/apac/in-the-press/asia-newsroom/2025/india-outpaces-global-average-with-2026-medical-trend-at-11-5-percent-aon-reports>

Retail Indian calculators commonly quote 13–14%. 11.5% is the conservative,
best-sourced figure.

---

## 1.3 Terminology — why people get stuck, and what to say instead

This section came out of actually trying to explain the safe withdrawal rate to
someone. Every sticking point below is a real one that came up, in order. The
fixes belong in the UI.

### Sticking point 1 — "5% of what, exactly?"

**Answer: 5% of your corpus on the day you retire.** It is scale-free:

| Corpus at retirement | 5% = your first-year income |
|---|---|
| ₹1 Cr | ₹5 lakh |
| ₹5 Cr | ₹25 lakh |
| ₹12.9 Cr | ₹64.5 lakh |

**The detail that must be stated explicitly:** you calculate that percentage
**once, on day one**, and then forget it. From then on you raise the *rupee
amount* by inflation each year. You do **not** recompute the percentage against
whatever the pot happens to be worth — that would collapse your income in a bad
market year, exactly when you can least afford it.

### Sticking point 2 — deriving the safe rate from the sequence demo

The sequence demonstration in §1.1 ends with the bad-first retiree broke in year
7 while withdrawing ₹8 lakh from ₹1 crore — an **8% rate**. The natural next
question is: what rate *would* have survived? Same two orderings, varying only
the withdrawal:

| Rate | Withdrawal | Good-first order | Bad-first order |
|---|---|---|---|
| 8% | ₹8.0 L | ₹0.57 Cr left | **broke year 7** |
| 7% | ₹7.0 L | ₹0.63 Cr left | **broke year 8** |
| 6% | ₹6.0 L | ₹0.69 Cr left | **broke year 10** |
| 5% | ₹5.0 L | ₹0.76 Cr left | ₹0.16 Cr left ✓ |
| 4% | ₹4.0 L | ₹0.82 Cr left | ₹0.34 Cr left ✓ |
| 3% | ₹3.0 L | ₹0.89 Cr left | ₹0.53 Cr left ✓ |

The lucky retiree survives **every** rate — at 8% they still finish with ₹57
lakh. Looking only at that column you would conclude 8% was fine. The unlucky
one only survives from **5%** down.

> **The definition falls straight out of the table:** the safe rate is the
> highest rate that still survives the *bad* ordering. It is set by the worst
> case, not the typical case — because you do not find out which column you are
> in until it is too late to act on.

**Caveat to carry into any UI copy:** that demo is 10 years with flat
withdrawals. Real retirements are 25–30+ years with inflation-adjusted
withdrawals, which is why the published Indian figure is 3–3.5%, not 5%. The
demo teaches the *mechanism*, not the number.

### Sticking point 3 — "lower rate should mean I need LESS, surely?"

This is the hardest one and it came up repeatedly. The reasoning is *"lower rate
→ I withdraw less → I need less corpus."* **The first half is right. The second
half answers a different question.**

There are two questions, and intuition answers the wrong one:

| | What is fixed | What you solve for | Lower rate means |
|---|---|---|---|
| **A** | your corpus (₹1 Cr) | your spending | spend **less** ✓ the intuition |
| **B** | your spending (₹34.6 L) | your corpus | need **more** |

**Question A** — I have ₹1 Cr, what income does it give me?

| Rate | You can spend |
|---|---|
| 5.00% | ₹5.00 L/yr |
| 4.00% | ₹4.00 L/yr |
| 3.25% | ₹3.25 L/yr |

**Question B** — I need ₹34.6 L/yr, how big must the pot be?

| Rate | You need |
|---|---|
| 5.00% | ₹6.92 Cr |
| 4.00% | ₹8.65 Cr |
| 3.25% | ₹10.64 Cr |

Both tables are correct. **The calculator asks B**, and it must, because *you do
not get to choose your spending*. Your life costs what it costs. The spending is
the input; the corpus is the unknown.

### The analogy that settles it: fixed deposit interest

Forget retirement entirely. You want to live off FD interest and you need
**₹1 lakh a year**:

```
  FD pays 8%   →  you must deposit  ₹12.5 lakh
  FD pays 4%   →  you must deposit  ₹25 lakh
  FD pays 2%   →  you must deposit  ₹50 lakh
```

Nobody finds that confusing. A worse rate obviously means a bigger deposit — the
money is less productive, so you need more of it for the same income.

**That is mathematically identical.** A safe rate of 3.25% rather than 5% is not
a lifestyle instruction to spend less. It is the news that **your rupees are
weaker than you thought**, so you need more of them for the same life. It should
feel exactly like FD rates dropping from 8% to 3%: your target did not change,
but the pile you need just got bigger.

### The real fix: stop using the percentage, use the multiple

The percentage form is a **reciprocal**, and reciprocals invert — which is the
entire source of the confusion. Flip it and the inversion disappears:

| Safe rate | Same thing as a multiple | Corpus needed |
|---|---|---|
| 5.00% | **20× annual expenses** | ₹6.92 Cr |
| 4.00% | **25×** | ₹8.65 Cr |
| 3.50% | **28.6×** | ₹9.88 Cr |
| 3.25% | **30.8×** | ₹10.64 Cr |
| 3.00% | **33.3×** | ₹11.53 Cr |
| 2.50% | **40×** | ₹13.84 Cr |

Read the middle and right columns together: **they move in the same direction.**
Safer plan → bigger multiple → bigger corpus. Nothing to invert mentally.

So instead of *"my safe withdrawal rate is 3.25%"*, say:

> **"I need about 31 years' worth of expenses saved up."**

And the research finding stops sounding paradoxical:

> *"Americans say 25× is enough. Indian data says 30–33×, because our inflation
> is higher and our markets are bumpier."*

### Sticking point 4 — "so can we just call it the interest rate?"

**No — and this is a real trap.** The app *already has* that parameter: the
slider called **"Return after retirement," currently 7%**. That genuinely is the
rate the corpus grows at. The safe rate is a different number. Reusing the name
would give two sliders the same label and different values.

The right question is: if the corpus grows at 7%, why can you only take 3.25%?

```
  corpus grows at                      7.00%
  your withdrawal ALSO grows at        6.00%   ← inflation; you need more rupees every year
  ─────────────────────────────────────────
  real growth you actually keep        0.94%
```

**This is what the FD analogy hides.** In an FD you take the same ₹1 lakh every
year forever. In retirement you cannot — ₹1 lakh will not buy in 2040 what it
buys today — so your withdrawal must climb 6% a year just to stand still. Most
of that 7% growth has to **stay in the pot** to fund next year's larger
withdrawal.

If you refused to ever touch principal you could take only **0.94%**. But you do
not live forever, so you are allowed to spend the principal down:

| Retirement length | You could take | = multiple |
|---|---|---|
| 17 years | 6.33% | 15.8× |
| 25 years | 4.47% | 22.4× |
| 30 years | 3.81% | 26.3× |
| 40 years | 2.98% | 33.5× |

Over 30 years that is **3.81% — if returns arrive perfectly smoothly.** They do
not. Shaving a margin for bad sequencing is what gets you to **~3.25%**.

```
  7.00%  growth
  −6.00% swallowed by inflation
  +      principal you are allowed to spend down over ~30 years
  −      safety margin for bad sequencing
  ───────────────────────────────────────
  3.25%  safe income rate
```

### The analogy that keeps the two rates apart: a rental flat

- The flat's **value appreciates** — say 7% a year. That is the *return*.
- The flat **pays rent** — say 3% of its value a year. That is the *income*.

Two different numbers describing the same asset. Nobody calls rent
"appreciation", and nobody is confused that a flat yielding less rent means you
need a bigger flat to live off.

**Your corpus is the flat. 7% is appreciation. 3.25% is the rent it can safely
pay you, for life, rising with inflation.**

### Conclusion: the words to use

| Current label | Use instead | What it actually is |
|---|---|---|
| Return after retirement (7%) | **Growth rate** | what the money *earns* |
| Safe withdrawal rate (3.25%) | **Safe income rate** | what it can safely *pay you* |
| "3.25%" | **"30.8× expenses"** | removes the reciprocal — the real fix |

"Withdrawal" is the wrong word because it describes **your behaviour** — a tap
you choose how far to open. The number describes **your money's capability**. It
should become *income*, not *interest*: income is what the money gives you,
growth is what the money does to itself.

### A note on writing style for UI copy

Avoid finance idiom. "Each rupee can safely **throw off** ₹X of income" is
standard finance English and was a genuine stumbling block — the reader is
already working through a hard concept and decorative language taxes them
further. Write **"produce"**, or better, **"pay you"**.

The one-sentence version worth putting somewhere prominent:

> **Each ₹1 crore of corpus can safely pay you about ₹3.25 lakh a year, for
> life, rising with inflation. You need ₹34.6 lakh a year. So you need about
> ₹10.6 crore.**

No percentages to invert. No "withdrawal". Just: how big a salary can each crore
pay me, and how many crores does my life cost?

---

# Part 2 — The two parameters, quantified

All figures below use a real worked scenario: age 39, retire at 58 (Y=19), plan
to 75 (N=17), 6% inflation, 7% post-retirement return, ₹11.43 lakh/year of
spending today, projected corpus ₹12.90 Cr.

## Parameter 1 — healthcare share of spending

**Input:** "What share of your spending today is healthcare?" Default **15%**.
Medical inflation pinned at **11.5%** (adjustable, but defaulted and sourced).

> **Design principle:** expose what the *user* knows (their own spending mix);
> hard-code what the *research* knows (the medical trend rate). A second
> free-floating inflation slider invites people to guess at a number they have
> no basis for.

Effect on required corpus (depletion method):

| Share today | Becomes, at 58 | Required corpus | Change |
|---|---|---|---|
| 0% | 0% | ₹5.46 Cr | — |
| 10% | 22.5% | ₹7.10 Cr | **+29.9%** |
| 15% | 31.6% | ₹7.91 Cr | **+44.9%** |
| 25% | 46.6% | ₹9.55 Cr | **+74.9%** |

## Parameter 2 — effective tax rate on withdrawals

**Input:** one percentage, default **8%**. Grosses up the withdrawal: to *spend*
₹100 you must *withdraw* ₹100/(1−t).

The model currently assumes every rupee withdrawn is a rupee you can spend. It
is not. The 2025 Indian SWR research found tax bracket alone moves the
sustainable rate by a **full percentage point** (3.5–4.2% low-bracket vs
2.7–3.2% at 30%) — larger than the gap between any two other assumptions here.

| Effective tax | Gross-up | Required corpus | Change |
|---|---|---|---|
| 0% | 1.000 | ₹5.46 Cr | — |
| 5% | 1.053 | ₹5.75 Cr | +5.3% |
| 8% | 1.087 | ₹5.94 Cr | **+8.7%** |
| 12% | 1.136 | ₹6.21 Cr | +13.6% |

**Honest caveat to document:** real Indian tax on an SWP touches only the *gain*
portion of each redemption, with a ₹1.25 lakh LTCG exemption, and the gain
fraction climbs over time. A flat rate is a simplification — but a one-input
approximation capturing most of the effect beats a zero-input model capturing
none.

## Combined effect

**Together: ₹5.46 Cr → ₹8.60 Cr, a +58% increase in required corpus.**

On the worked scenario, the verdict itself flips:

| | First-year need | Required | Funded | Verdict |
|---|---|---|---|---|
| As the app stands | ₹34.6 L | ₹10.64 Cr | 121% | Comfortably ahead |
| + healthcare split | ₹43.0 L | ₹13.22 Cr | 98% | On track |
| + healthcare and tax | ₹46.7 L | ₹14.37 Cr | **90%** | **Slightly behind** |

A calculator that tells someone to relax when they should not has failed at the
only job it has. That is the argument for doing this work.

## Why these two, and not the other candidates

| Candidate | Why not first |
|---|---|
| **Monte Carlo / volatility** | Not a parameter — an architecture change. The SWR method already headlining the page buys partial insurance against sequence risk, so marginal value is lower than it looks. |
| **One-off goals** (education, wedding) | Can be ₹1 Cr of compounded impact, but it is a missing *feature*, not a bias — a childless user's correction is zero. Needs amounts *and* dates, so 3 inputs. |
| **Separate EPF/PPF/NPS buckets** | Moves the answer by low single digits. An order of magnitude smaller. |
| **Glide path** | Second-order. |
| **Couples / joint life expectancy** | Doubles the model. |

Decisive criterion: healthcare and tax are the only two that bias the answer
**in a predictable direction for every user**. Both always mean you need more.

---

# Part 3 — Implementation plan

## 3.1 `backend/src/Types.hs`

Add three fields to `PlanInput` (two user-facing, one defaulted):

```haskell
  , medicalSharePercent     :: Double
    -- ^ Share of today's spending that is healthcare: premiums PLUS everything
    -- insurance does not pay (co-pays, outpatient, dental, long-term care).
    -- Not zero just because you hold a policy — the policy is itself the thing
    -- inflating at the medical rate.
  , medicalInflationPercent :: Double
    -- ^ Aon's 2026 India medical trend. Defaulted and sourced; exposed for
    -- stress-testing rather than for routine guessing.
  , effectiveTaxRatePercent :: Double
    -- ^ Flat effective tax on withdrawals. A simplification of LTCG-on-gains,
    -- documented as such.
```

Defaults in `defaultInput`: `15`, `11.5`, `8`.

Add to `Summary`, for the UI to show the effect:

```haskell
  , medicalShareAtRetirement :: Double   -- the 15% -> 31.6% story
  , annualMedicalNeed        :: Rupees
  , annualGeneralNeed        :: Rupees
  , grossWithdrawalNeeded    :: Rupees   -- after tax gross-up
```

## 3.2 `backend/src/Calculator.hs`

**The good news: no new maths.** The existing `pvOfInflatingWithdrawals`
already handles a negative real rate correctly, so the two-stream version is
just two calls to it:

```haskell
-- | Required corpus with healthcare split out as its own stream.
--
-- Healthcare inflates far faster than everything else, which against a 7%
-- portfolio means a NEGATIVE real return — a different regime, and one the
-- existing annuity formula already handles. Splitting the stream in two is
-- therefore a matter of calling it twice, not of new mathematics.
requiredByDepletion postReturn generalInfl medicalInfl n generalNeed medicalNeed =
    pvOfInflatingWithdrawals postReturn generalInfl n generalNeed
  + pvOfInflatingWithdrawals postReturn medicalInfl n medicalNeed
```

Splitting the need at retirement (note each stream inflates from **today**, at
its own rate — this is what makes the share rise on its own):

```haskell
generalToday = annualExpenseToday * (1 - medicalShare)
medicalToday = annualExpenseToday * medicalShare

generalAtRet = compoundFor inflation        yearsToRet generalToday
medicalAtRet = compoundFor medicalInflation yearsToRet medicalToday
```

Tax gross-up:

```haskell
-- | To SPEND this much you must WITHDRAW more, because the taxman takes a cut
-- on the way out. Guarded against a rate of 100%, which would demand an
-- infinite corpus.
grossUpForTax :: Rate -> Rupees -> Rupees
grossUpForTax (Rate t) net
  | t >= 1 - epsilon = net / epsilon   -- or reject in `validate`
  | otherwise        = net / (1 - t)
```

**`drawdownSchedule` must also be split**, or the year-by-year table will stop
matching the headline. Each year now withdraws
`general × (1+i)^(k-1) + medical × (1+im)^(k-1)`, grossed up for tax.

Consider adding a `drwMedicalPortion` column so the table shows healthcare
eating the budget year by year — that is the whole story made visible.

**Validation to add in `validate`:**

- `medicalSharePercent` in 0–60
- `medicalInflationPercent` in 0–25
- `effectiveTaxRatePercent` in 0–40

## 3.3 Self-checks to add in `selfChecks`

The regression guards matter most — they prove the change is strictly additive:

1. **`medicalSharePercent = 0` reproduces today's answer exactly.**
2. **`effectiveTaxRatePercent = 0` reproduces today's answer exactly.**
3. Medical share at retirement exceeds the share today whenever
   `medicalInflation > inflation` (15% → ~31.6% on the reference scenario).
4. The medical stream's real return is negative at the defaults — assert it, so
   nobody "fixes" the formula later thinking it is a bug.
5. Gross-up round-trip: `grossUpForTax t x * (1 - t) == x`.
6. Required corpus is **monotonically increasing** in both new parameters.

Checks 1 and 2 are the important ones. If they fail, the change has altered
existing behaviour and something is wrong.

## 3.4 Frontend

- Two `NumberField`s in `InputPanel.svelte`, in the **"Your money today"**
  section (medical share — it is a fact about you) and **"Assumptions"** (tax
  rate — it is a guess).
- Hints must carry the teaching, briefly: *"Premiums plus everything insurance
  doesn't pay. Not zero just because you're insured — your policy is itself
  inflating at 11.5%."*
- New `StatTile`: *"Healthcare share of spending at 58"* showing **15% → 31.6%**.
  This is the most persuasive single number the change produces.
- Consider a stacked area on the drawdown chart: general vs medical withdrawals
  over time, using the already-validated blue/aqua pair. The medical wedge
  visibly swallowing the chart is the argument, made without words.

## 3.5 `ASSUMPTIONS.md` updates

Move healthcare and tax **out** of §7.1 ("what the model leaves out") and into
§2/§3 as documented parameters. Keep the caveat that the tax treatment is a flat
approximation of LTCG-on-gains. Update §6 (deliberate divergences) — no other
Indian calculator does either of these, which is worth stating plainly.

---

---

# Part 4 — Change 3: rename the safe withdrawal rate

**Independent of changes 1 and 2. Ship it first — it is ~15 minutes and
touches no arithmetic.** Nothing below alters a single computed number; it
changes only what the page calls things.

Rationale is in §1.3. In short: "withdrawal rate" names the wrong noun, and the
percentage form is a reciprocal that inverts in the reader's head.

## 4.1 `frontend/src/lib/InputPanel.svelte`

Relabel the field and rewrite the hint using the rent framing and plain words:

```svelte
<NumberField
  label="Safe income rate"
  bind:value={input.safeWithdrawalRatePercent}
  min={2.5} max={5} step={0.05} suffix="% a year"
  hint="Each ₹1 crore of corpus can safely pay you about ₹{...} a year for life,
        rising with inflation. This is NOT the same as the {post-retirement
        return}% your corpus earns — most of that is eaten by inflation.
        Indian studies land at 3–3.5%; the American 4% rule does not transfer."
/>
```

Consider relabelling **"Return after retirement" → "Growth rate after
retirement"** at the same time, so the pair reads as *growth* vs *income*
rather than two unrelated percentages.

## 4.2 Show the multiple live, next to the rate

The single highest-value part of this change. As the slider moves, show:

> **3.25% — you need 30.8× your annual expenses**

The multiple is `100 / safeWithdrawalRatePercent`. Computing it in the frontend
would violate the project's rule that all arithmetic lives in Haskell, so add it
to `Summary` instead:

```haskell
  , safeIncomeMultiple :: Double   -- 100 / safeWithdrawalRatePercent
```

It is already effectively present as `corpusMultipleRequired` when the SWR
method wins, but a dedicated field is clearer and holds even when the depletion
method is the larger one.

## 4.3 `frontend/src/lib/ResultsPanel.svelte`

- The existing tile note reads *"30.8× your first year of retirement
  spending"*. Promote that from small print — it is the non-inverting form and
  should be as prominent as the percentage.
- Rename the stat tile **"Withdrawal rate this plan implies"** →
  **"Income rate this plan implies"**, matching the input.
- In the two-methods card, replace *"drawing 3.25% a year is sustainable
  indefinitely"* with *"holding about 31× your annual expenses"*.

## 4.4 Field name in the API

Leave `safeWithdrawalRatePercent` as the JSON/Haskell field name. It matches the
published literature, and renaming it would churn `Types.hs`, `Calculator.hs`,
the self-checks and the frontend for no functional gain. **This change is about
what the human reads, not what the code calls things.** Add a comment in
`Types.hs` noting the UI label differs and why.

## 4.5 `ASSUMPTIONS.md`

Keep "safe withdrawal rate" as the primary term there — it is the term used in
every source cited — but add the gloss *"shown in the app as 'safe income
rate'"* on first use, plus the multiple alongside every percentage.

---

## Open questions to settle before coding

1. **Does the SWR method need its own treatment?**
   The safe-withdrawal method assumes *constant real spending*. With healthcare
   split out, real spending **rises** every year, so
   `corpus = first-year need / SWR` understates the requirement. Options:
   (a) accept it and document; (b) apply the SWR to a
   duration-weighted average need; (c) lower the effective SWR in proportion to
   the medical share. **(a) is probably right for now** — the method is already
   the conservative one of the two, and option (c) risks double-counting.

2. **Should medical inflation be visible at all, or fixed at 11.5%?**
   Leaning towards visible-but-defaulted. Users who want to stress-test at 14%
   should be able to; users who do not should never have to think about it.

3. **Does the medical share keep growing *during* retirement?**
   Under the two-stream model it does, automatically — correct, and it is the
   realistic behaviour. Worth sanity-checking that it does not reach an absurd
   share (>70%) by age 85 under default inputs. If it does, consider capping
   medical inflation after a certain age.

4. **Default medical share of 15% — defend or revise?**
   Reasonable for an insured, healthy mid-career person once out-of-pocket is
   included. Worth a second look for users already near retirement, where the
   starting share should be higher.

## Suggested order of work

**Warm-up — change 3, the rename (~15 min, no arithmetic touched):**

1. Add `safeIncomeMultiple` to `Summary` in `Types.hs` and `Calculator.hs`.
2. Relabel the field in `InputPanel.svelte`, rewrite the hint, show the multiple
   live beside the slider.
3. Rename the matching stat tile in `ResultsPanel.svelte`.

**Main work — changes 1 and 2 (~1–1.5 hrs):**

4. `Types.hs` fields and defaults (smallest, unblocks everything).
5. `Calculator.hs` two-stream required corpus + tax gross-up.
6. **Self-checks 1 and 2 before anything else** — prove that a zero medical
   share and a zero tax rate reproduce today's answers *exactly*. If they do
   not, the change has broken existing behaviour.
7. `drawdownSchedule` split, so the year-by-year table matches the headline.
8. Frontend fields and the share-at-retirement tile.

**If time allows:**

9. Stacked drawdown chart — general vs medical withdrawals, blue/aqua pair.
10. `ASSUMPTIONS.md` rewrite: move healthcare and tax out of §7.1 (omissions)
    and into §2/§3 (documented parameters).

Steps 4–6 are the only real thinking. Everything else is presentation.

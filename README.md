# Retirement calculator — India

A retirement corpus calculator for India that models inflation, healthcare costs and tax on withdrawals.
Built with a Haskell (Scotty) backend that does all the maths and a Svelte frontend that draws it.

---

A small web app that answers one question: **given what I earn, spend and have
saved, am I on course for the retirement I want?**

- **Frontend:** Svelte 5 + Vite
- **Backend:** Haskell (Scotty) — *all* arithmetic happens here
- **Charts:** hand-rolled SVG, no charting library

The split is strict and deliberate: the frontend performs **no retirement
arithmetic at all**. Every number on screen, including every chart coordinate,
is computed by the Haskell backend. There is exactly one implementation of the
formulas, so the charts can never disagree with the figures printed beside them.

> **Read [`ASSUMPTIONS.md`](./ASSUMPTIONS.md) before trusting any output.** It
> documents every formula, justifies every default, and — most importantly —
> lists what the model leaves out and where it is most likely to be wrong.
>
> Healthcare (its own tapering inflation, plus ageing) and tax on withdrawals
> (estimated from the 2026-27 slabs) are now modelled — see `ASSUMPTIONS.md`
> §3.9–3.10. On the default scenario they raise the required corpus by about
> 49%. [`PROPOSED-IMPROVEMENTS.md`](./PROPOSED-IMPROVEMENTS.md) still holds the
> unbuilt rename of the safe withdrawal rate.

---

## Running it

You need **GHC ≥ 9.4 with cabal** and **Node 20.19+ or 22.12+**. Two terminals:

### 1. Backend

```bash
cd backend
cabal run
```

Serves on `http://127.0.0.1:8080` (loopback only). On start-up it runs 24 arithmetic
self-checks and **refuses to boot if any fail** — a calculator that is silently
wrong is worse than one that does not run.

```
Running arithmetic self-checks...
  PASS  compound interest: 1,00,000 at 10% for 10 years = 2,59,374
  PASS  real rate uses Fisher, not subtraction: 7% vs 6% = 0.9434%, not 1%
  ...
All 24 checks passed.
```

### 2. Frontend

```bash
cd frontend
npm ci
npm run dev
```

Open `http://localhost:5173`. Vite proxies `/api` to the backend.

---

## How it is laid out

```
backend/
  retirement-calculator.cabal
  cabal.project          Pins `warp -x509` — see note below
  src/
    Types.hs             Every value crossing the wire; no maths
    Calculator.hs        All the financial maths, and nothing else
    Tax.hs               Indian tax on withdrawals (2026-27 new regime), in one place
    Api.hs               Routes, JSON, status codes; knows nothing of retirement
    Main.hs              Runs the self-checks, then serves

frontend/
  src/
    app.css              Design tokens — the validated chart palette lives here
    App.svelte           Owns the input state, fetches results, debounces
    lib/
      api.js             The only module that knows the backend exists
      format.js          Indian number formatting (lakh/crore grouping)
      NumberField.svelte One labelled input + slider
      InputPanel.svelte  The questions
      ResultsPanel.svelte The answer
      StatTile.svelte    One headline number
      DataTable.svelte   Year-by-year numbers behind the charts
      charts/
        LineChart.svelte Multi-series line/area with a hover layer
        BarChart.svelte  Horizontal bars, optionally stacked

ASSUMPTIONS.md           Formulas, defaults, caveats, sources
PROPOSED-IMPROVEMENTS.md Design notes and the roadmap
```

### API

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/api/health` | Liveness probe |
| `GET` | `/api/defaults` | The starting scenario, so the form's defaults live next to the maths |
| `POST` | `/api/calculate` | The projection. Returns summary + both year-by-year schedules |

Invalid inputs come back as `400` with a message written for the person who
typed them, not a stack trace.

---

## Design notes

**The gap is stated in rupees a month.** Under the headline percentage the
page says how far behind or ahead you are (e.g. −28%) and turns that into the
change to your monthly investment that closes it (e.g. +₹15,271 a month,
+51%). The two percentages differ on purpose — see `ASSUMPTIONS.md` §3.7a.

**Check the units on each field.** Spending, investing and other income are
monthly; healthcare is yearly and means what it will cost *once retired*, not
today's premium. `ASSUMPTIONS.md` §2.1 explains how to arrive at it.

**There is no "Calculate" button.** The projection re-runs automatically,
debounced at 180ms, as soon as any field changes. The whole value of the tool is
seeing what moves when an assumption moves, and a submit button puts a wall
between the question and the answer. The previous result stays on screen while a
new one is in flight, so the charts never flash empty mid-drag.

**Colour follows the entity, everywhere.** Blue is always "you", orange is
always "the target", aqua is always "the part still to be invested" — in every
chart on the page. The three are slots 1–3 of a colourblind-safe categorical
palette, validated against both the light and dark surfaces for lightness band,
chroma, CVD separation and contrast. The reader only has to learn it once.

**The drawdown chart is plotted in today's rupees, not future rupees.** This is
not cosmetic. Whenever returns beat the withdrawal rate the *nominal* corpus
grows right through retirement — in the default scenario it climbs from
₹12.5 Cr to ₹21 Cr — which looks like getting richer and is nothing of the
sort, because prices climbed alongside. In today's purchasing power the same
plan correctly shows a decline from ₹2.3 Cr to ₹0.95 Cr. The table gives both.

**Two methods, and the larger wins.** There are two defensible ways to compute
the corpus you need, and for Indian inputs they differ by 30–50%. Most
calculators show only the smaller one. This one shows both and headlines the
larger. [`ASSUMPTIONS.md` §4](./ASSUMPTIONS.md) explains why that matters more
than anything else on the page.

---

## A build note

`backend/cabal.project` pins `constraints: warp -x509`. Warp's `x509` flag
pulls in `crypton`, whose hand-written x86 assembly does not assemble under the
clang shipped with recent macOS/Xcode (it fails in `bignum_emontredc_8n.S`).
The flag only exposes a client's TLS certificate to the application; this server
speaks plain HTTP on localhost and never asks for one, so disabling it costs
nothing and removes a large, fragile C dependency.

---

## Accuracy

The target is **±10%**, and that is an honest statement about a model whose
inputs are guesses about the next thirty years, not a limitation of the
arithmetic — which is exact and self-checked.

Tax is an estimate from today's slabs, assumed to keep pace with inflation;
healthcare is a smooth rising trend, not the lumpy reality of a hospital stay;
and returns are assumed to arrive smoothly rather than in the lumpy order real
markets deliver them.

**Not financial advice.** For a real plan, talk to a SEBI-registered investment
adviser.

---

## Contributing

Issues and pull requests are welcome. If a change touches the maths, add a
self-check to `selfChecks` in `backend/src/Calculator.hs` and update
`ASSUMPTIONS.md` so the documentation keeps matching the code.

## License

[MIT](./LICENSE) © Prasanna Kumar

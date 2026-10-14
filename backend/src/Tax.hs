-- |
-- Module      : Tax
-- Description : Indian income tax on a retiree's withdrawals, and nothing else.
--
-- == Which rules
--
-- The __new regime__ for tax year 2026-27 (the Income-tax Act 2025 took effect
-- on 1 April 2026; Budget 2026 left the rates unchanged).  The new regime is
-- the default, and about 88% of individual filers chose it in AY 2025-26.  The
-- old regime is not modelled: its senior-citizen extras (higher exemption,
-- 80TTB) only win for retirees with large deductions.
--
-- Every number that a Finance Act can change sits in the constants block
-- directly below, so a future Budget is a one-place edit.
--
-- == What is taxed
--
-- A withdrawal from a mutual-fund corpus is a redemption of units, and only the
-- /gain/ inside each redemption is income.  So a withdrawal @W@ with gain
-- fraction @g@ and equity share @e@ produces:
--
-- * equity gains  @e × W × g@        → 12.5% above ₹1.25 lakh (long-term)
-- * debt gains    @(1 − e) × W × g@  → slab rates (debt funds bought after
--   1 April 2023 are taxed at slab whatever the holding period)
--
-- plus any other income (pension, rent), also at slab.
--
-- == Simplifications, stated once
--
-- * All gains are treated as long-term.  A retiree selling the oldest units
--   first is selling units years old, so this is close to true.
-- * Debt is treated as debt mutual funds.  FD and SCSS interest is taxed on the
--   whole interest every year, not on redemption, so an FD-heavy retiree pays
--   more than this module says — they should use the flat-rate mode instead.
-- * Other income is taxed in full: no 30% deduction for rent, no ₹75,000
--   standard deduction for a pension.  Both err towards more tax.
-- * Surcharge marginal relief is ignored.  It only matters within a few
--   lakh of the ₹50 lakh / ₹1 crore / ₹2 crore thresholds.
--
-- == Today's rupees
--
-- Everything here is computed in __today's rupees__ against today's slabs.
-- 'Calculator' deflates each future year's amounts before calling in and
-- inflates the tax back afterwards.  That is the assumption that slabs keep
-- pace with inflation over the long run.  They are not indexed by law; they
-- are revised ad hoc (Budgets 2023 and 2025 both raised them).  If they froze,
-- tax would creep up over a thirty-year retirement.
module Tax
  ( TaxableYear(..)
  , taxOnYear
  , slabTax
  , grossUpForSlabTax
    -- * Constants, exported for the self-checks and for reading
  , rebateLimit
  , ltcgExemption
  , ltcgRate
  , basicExemption
  ) where

import Types (Rupees)

--------------------------------------------------------------------------------
-- The rules for tax year 2026-27, new regime
--------------------------------------------------------------------------------

-- | Slab ceilings and the rate applying up to each.  Above the last ceiling the
-- top rate applies.
slabs :: [(Rupees, Double)]
slabs =
  [ (400000,  0.00)
  , (800000,  0.05)
  , (1200000, 0.10)
  , (1600000, 0.15)
  , (2000000, 0.20)
  , (2400000, 0.25)
  ]

topRate :: Double
topRate = 0.30

-- | The income below which no slab tax is payable at all.  Unused, it can also
-- be set against long-term equity gains (residents only).
basicExemption :: Rupees
basicExemption = 400000

-- | Section 87A: no slab tax if /normal/ income is at most ₹12 lakh, with
-- marginal relief just above.  The rebate does not reach special-rate capital
-- gains (Finance Act 2025), so equity gains are kept out of this test.
rebateLimit :: Rupees
rebateLimit = 1200000

-- | Long-term equity gains: the first ₹1.25 lakh a year is exempt, the rest is
-- taxed at 12.5% (Budget July 2024, unchanged since).
ltcgExemption :: Rupees
ltcgExemption = 125000

ltcgRate :: Double
ltcgRate = 0.125

-- | Health and education cess, on top of tax and surcharge.
cess :: Double
cess = 0.04

-- | Surcharge by total income.  The new regime caps it at 25%.
surchargeRate :: Rupees -> Double
surchargeRate income
  | income > 20000000 = 0.25
  | income > 10000000 = 0.15
  | income >  5000000 = 0.10
  | otherwise         = 0

-- | Surcharge on long-term equity gains is capped at 15%.
ltcgSurchargeCap :: Double
ltcgSurchargeCap = 0.15

--------------------------------------------------------------------------------
-- The calculation
--------------------------------------------------------------------------------

-- | Slab tax on normal income, before rebate, surcharge and cess.
--
-- > slabTax 1600000  ==  120000    -- 20k + 40k + 60k
slabTax :: Rupees -> Rupees
slabTax income = go 0 slabs
  where
    go floor' [] = max 0 (income - floor') * topRate
    go floor' ((ceiling', rate) : rest)
      | income <= ceiling' = (income - floor') * rate
      | otherwise          = (ceiling' - floor') * rate + go ceiling' rest

-- | One retirement year's taxable amounts, in today's rupees.
data TaxableYear = TaxableYear
  { tyNormalIncome :: Rupees  -- ^ Slab-rate income: debt gains plus pension or rent.
  , tyEquityGains  :: Rupees  -- ^ Long-term gains on equity units redeemed.
  }

-- | Total tax for the year, including surcharge and cess.
--
-- The order matters and follows the Act:
--
-- 1. Slab tax on normal income, rebated to zero at or below ₹12 lakh, and
--    capped at the excess over ₹12 lakh just above it (marginal relief).
-- 2. Any basic exemption the normal income did not use is set against equity
--    gains, after the ₹1.25 lakh exemption.
-- 3. Surcharge by total income (capped at 15% on the equity-gains part), then
--    cess on everything.
taxOnYear :: TaxableYear -> Rupees
taxOnYear (TaxableYear normal equityGains) =
  (normalTax * (1 + sc) + gainsTax * (1 + min sc ltcgSurchargeCap)) * (1 + cess)
  where
    rawSlab   = slabTax normal
    normalTax
      | normal <= rebateLimit = 0
      | otherwise             = min rawSlab (normal - rebateLimit)

    unusedExemption = max 0 (basicExemption - normal)
    taxableGains    = max 0 (equityGains - ltcgExemption - unusedExemption)
    gainsTax        = taxableGains * ltcgRate

    sc = surchargeRate (normal + equityGains)

-- | The gross withdrawal needed this year, given what is spent and what other
-- income arrives.
--
-- Spending and tax are paid from other income first and the corpus only
-- covers what is left:
--
-- > W = max 0 (spending + tax(W) − otherIncome)
--
-- Tax depends on the withdrawal (it creates taxable gains) and the withdrawal
-- must cover the tax, so this is a fixed point.  Iterating from
-- @W = max 0 (spending − otherIncome)@ converges because the top marginal
-- rate (about 39% with surcharge and cess) is well below 100% — each round
-- adds less than the round before.  The iteration stops once a round moves
-- the answer by less than a rupee.
--
-- The order matters.  Flooring @spending − otherIncome@ at zero /before/
-- adding tax would throw away any surplus income and then charge the tax on
-- that income to the corpus: a ₹24 lakh pension against ₹7.2 lakh of spending
-- would demand a corpus to pay a tax bill the pension covers several times
-- over.  Netting spending, tax and income together, then flooring, is what
-- lets surplus income pay its own tax.
grossUpForSlabTax
  :: Double  -- ^ equity share of the corpus, 0–1
  -> Double  -- ^ gain fraction of each rupee redeemed, 0–1
  -> Rupees  -- ^ other taxable income for the year (pension, rent)
  -> Rupees  -- ^ the year's total spending, before other income
  -> Rupees  -- ^ gross withdrawal from the corpus
grossUpForSlabTax equityShare gainFraction otherIncome spending =
  go (50 :: Int) (withdrawalFor 0)
  where
    -- The whole year's tax, including the tax on the pension or rent itself.
    taxFor w = taxOnYear TaxableYear
      { tyNormalIncome = otherIncome + (1 - equityShare) * w * gainFraction
      , tyEquityGains  = equityShare * w * gainFraction
      }

    withdrawalFor tax = max 0 (spending + tax - otherIncome)

    go 0 w = w
    go n w =
      let w' = withdrawalFor (taxFor w)
      in if abs (w' - w) < 1 then w' else go (n - 1) w'

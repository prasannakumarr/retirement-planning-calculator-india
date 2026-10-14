-- New-regime Indian income tax, tax year 2026-27. All amounts in today's rupees.
module Tax
  ( TaxableYear(..)
  , taxOnYear
  , slabTax
  , grossUpForSlabTax
  , rebateLimit
  , ltcgExemption
  , ltcgRate
  , basicExemption
  ) where

import Types (Rupees)

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

basicExemption :: Rupees
basicExemption = 400000

-- The 87A rebate does not apply to special-rate equity gains.
rebateLimit :: Rupees
rebateLimit = 1200000

ltcgExemption :: Rupees
ltcgExemption = 125000

ltcgRate :: Double
ltcgRate = 0.125

cess :: Double
cess = 0.04

surchargeRate :: Rupees -> Double
surchargeRate income
  | income > 20000000 = 0.25
  | income > 10000000 = 0.15
  | income >  5000000 = 0.10
  | otherwise         = 0

ltcgSurchargeCap :: Double
ltcgSurchargeCap = 0.15

slabTax :: Rupees -> Rupees
slabTax income = go 0 slabs
  where
    go floor' [] = max 0 (income - floor') * topRate
    go floor' ((ceiling', rate) : rest)
      | income <= ceiling' = (income - floor') * rate
      | otherwise          = (ceiling' - floor') * rate + go ceiling' rest

data TaxableYear = TaxableYear
  { tyNormalIncome :: Rupees
  , tyEquityGains  :: Rupees
  }

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

-- Fixed point W = max 0 (spending + tax(W) - otherIncome). Floor only after
-- netting, so surplus other income pays its own tax.
grossUpForSlabTax
  :: Double
  -> Double
  -> Rupees
  -> Rupees
  -> Rupees
grossUpForSlabTax equityShare gainFraction otherIncome spending =
  go (50 :: Int) (withdrawalFor 0)
  where
    taxFor w = taxOnYear TaxableYear
      { tyNormalIncome = otherIncome + (1 - equityShare) * w * gainFraction
      , tyEquityGains  = equityShare * w * gainFraction
      }

    withdrawalFor tax = max 0 (spending + tax - otherIncome)

    go 0 w = w
    go n w =
      let w' = withdrawalFor (taxFor w)
      in if abs (w' - w) < 1 then w' else go (n - 1) w'

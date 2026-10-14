{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Types
-- Description : The vocabulary of the retirement calculator.
--
-- This module defines every value that crosses the wire between the Svelte
-- frontend and this Haskell backend, plus the two small newtypes that the
-- arithmetic is written against.
--
-- Nothing in here does any maths.  It only describes shapes.  All of the
-- actual financial logic lives in "Calculator", so that the formulas can be
-- read (and audited) in one place without HTTP or JSON noise around them.
module Types
  ( -- * Scalar wrappers
    Rupees
  , Rate(..)
  , ratePercent
  , growthFactor

    -- * Request
  , PlanInput(..)
  , TaxMode(..)
  , defaultInput

    -- * Response
  , PlanResult(..)
  , Summary(..)
  , AccumulationRow(..)
  , DrawdownRow(..)
  , Verdict(..)
  , CalcError(..)
  ) where

import           Data.Aeson   (FromJSON (..), ToJSON (..), defaultOptions,
                               genericParseJSON, genericToJSON, toEncoding,
                               genericToEncoding)
import           Data.Text    (Text)
import           GHC.Generics (Generic)

--------------------------------------------------------------------------------
-- Scalars
--------------------------------------------------------------------------------

-- | An amount of money in Indian rupees.
--
-- This is a plain type alias rather than a newtype: money is added,
-- subtracted and scaled constantly throughout the calculation, and wrapping it
-- would cost a lot of unwrapping noise for very little safety.  The unit is
-- always /rupees/ (never lakhs, never crores) — the frontend is responsible
-- for formatting large numbers into lakh/crore notation for display.
type Rupees = Double

-- | A rate of return or inflation, stored as a __decimal fraction__.
--
-- @Rate 0.06@ means 6% per annum.
--
-- This one /is/ a newtype, and deliberately so.  Mixing up "6" and "0.06" is
-- the single most common blunder in compound-interest code, and it fails
-- silently — you just get an answer that is wrong by orders of magnitude.
-- Forcing every rate through 'ratePercent' means the conversion happens
-- exactly once, at the boundary where the user's "6" arrives.
newtype Rate = Rate { unRate :: Double }
  deriving (Show, Eq)

-- | Build a 'Rate' from a human-entered percentage.
--
-- > ratePercent 6.5  ==  Rate 0.065
ratePercent :: Double -> Rate
ratePercent p = Rate (p / 100)

-- | The multiplier that one period of growth at this rate applies.
--
-- > growthFactor (Rate 0.06)  ==  1.06
--
-- Almost every compounding step in "Calculator" is expressed in terms of this
-- function rather than by writing @1 + r@ inline, so that the "+1" can never
-- be forgotten in one place and remembered in another.
growthFactor :: Rate -> Double
growthFactor (Rate r) = 1 + r

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

-- | Everything the user fills in on the form.
--
-- All percentages arrive as plain numbers (@6.5@ meaning 6.5% p.a.) and all
-- money arrives in __today's rupees__ — i.e. what the amount is worth now, not
-- what it will be worth at retirement.  Converting today's rupees into
-- retirement-date rupees is the calculator's job, not the user's.
data PlanInput = PlanInput
  { currentAge              :: Double
    -- ^ Age today, in years.
  , retirementAge           :: Double
    -- ^ Age at which salary/business income stops and withdrawals begin.
  , lifeExpectancy          :: Double
    -- ^ Age the corpus must last until.  This is a /planning/ age, not a
    -- prediction: it should be set generously, because running out of money at
    -- 85 when you live to 92 is a far worse error than leaving money behind.
  , currentMonthlyExpense   :: Rupees
    -- ^ Current household spending per month, in today's rupees, after tax
    -- and __excluding healthcare__, which is 'healthcareAnnualToday'.  This —
    -- not income — is what drives the required corpus, because retirement has
    -- to replace your /spending/, not your salary.
  , currentCorpus           :: Rupees
    -- ^ Retirement savings already accumulated (EPF + PPF + NPS + equity MFs +
    -- FDs earmarked for retirement).  Deliberately excludes the home you live
    -- in, which cannot be spent.
  , monthlyInvestment       :: Rupees
    -- ^ Amount currently invested towards retirement every month.
  , annualStepUpPercent     :: Double
    -- ^ Yearly percentage increase in 'monthlyInvestment', tracking salary
    -- growth.  A step-up is the single biggest lever most people have, which
    -- is why it is a first-class input rather than an assumption.
  , inflationPercent        :: Double
    -- ^ General consumer inflation, used both to inflate today's expenses up
    -- to the retirement date and to grow withdrawals during retirement.
  , preRetirementReturnPercent  :: Double
    -- ^ Expected nominal annual return while still accumulating, when the
    -- portfolio can afford to be equity-heavy.
  , postRetirementReturnPercent :: Double
    -- ^ Expected nominal annual return after retiring, when the portfolio must
    -- shift towards debt and capital protection.  Always lower than the
    -- pre-retirement figure.
  , expenseAdjustmentPercent :: Double
    -- ^ A one-off lifestyle adjustment applied at retirement, as a percentage.
    -- Negative means spending falls (no commute, no EMI, children
    -- independent); positive means it rises (travel).  Applies to living
    -- costs only; healthcare has its own stream.  Default 0,
    -- which assumes you will spend exactly as much as you do now.
  , otherMonthlyIncome      :: Rupees
    -- ^ Optional inflation-linked income during retirement in today's rupees —
    -- typically rent.  Subtracted from the amount the corpus has to provide,
    -- and taxed at slab rates in full when tax is estimated from slabs.
    -- Set to 0 if unsure; that is the conservative choice.
  , safeWithdrawalRatePercent :: Double
    -- ^ The percentage of the corpus that can be withdrawn in the first year of
    -- retirement and sustained, inflation-adjusted, thereafter.
    --
    -- This drives the /second/ of the two required-corpus methods — see
    -- "Calculator" for why there are two.  The familiar American "4% rule"
    -- does not survive the move to India: published Indian studies
    -- (Saraogi 2024; Basunivesh's Monte Carlo on Nifty TRI + G-Sec) put the
    -- sustainable figure at 3–3.5%, so the default here is 3.25%, equivalent
    -- to targeting roughly 31× annual expenses.
  , healthcareAnnualToday   :: Rupees
    -- ^ Healthcare per year once retired, priced in __today's__ rupees:
    -- premiums for retail cover plus everything insurance does not pay
    -- (co-pays, room-rent gaps, outpatient, medicines, dental).
    --
    -- Asked for in rupees rather than as a share of spending because people
    -- know their premium; they do not know their spending mix.  And it is a
    -- /retirement/ figure on purpose: while working, an employer's group
    -- policy hides most of the cost, and that cover ends on the last day of
    -- work.  'currentMonthlyExpense' should therefore exclude healthcare.
  , medicalInflationPercent :: Double
    -- ^ Healthcare cost inflation in the near term.  It tapers from this rate
    -- down to general inflation + 2 points over 20 years — see
    -- 'Calculator.medicalRateInYear' for why it cannot stay high for ever.
  , healthcareAgeingPercent :: Double
    -- ^ Extra yearly growth in healthcare cost from getting older, applied
    -- from age 60 to 85.  This is separate from price inflation: insurers'
    -- trend rates are measured on a working population whose average age
    -- does not change, so they leave ageing out.
  , taxMode                 :: TaxMode
  , flatTaxRatePercent      :: Double
    -- ^ Used only when 'taxMode' is 'FlatRate': tax as a share of every rupee
    -- withdrawn.
  , equitySharePercent      :: Double
    -- ^ Share of the retirement corpus held in equity funds.  Used only by
    -- 'EstimateFromSlabs', because equity and debt gains are taxed
    -- differently.
  } deriving (Show, Generic)

instance FromJSON PlanInput where
  parseJSON = genericParseJSON defaultOptions

instance ToJSON PlanInput where
  toJSON    = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

-- | How tax on withdrawals is handled.
data TaxMode
  = EstimateFromSlabs
    -- ^ Work it out each year from the new-regime slabs and the 12.5% equity
    -- gains rate, taxing only the gain inside each withdrawal.  See "Tax".
  | FlatRate
    -- ^ A single rate on every rupee withdrawn.  For FD/SCSS-heavy retirees,
    -- whose interest is fully taxable, or anyone who prefers a round number.
  | NoTax
    -- ^ Ignore tax — for people who have already entered after-tax returns.
  deriving (Show, Eq, Generic)

instance FromJSON TaxMode
instance ToJSON TaxMode

-- | A reasonable starting scenario for a mid-career Indian professional.
--
-- The frontend fetches this so that the form opens pre-filled with sane,
-- defensible numbers rather than empty boxes.  The justification for each
-- figure is written up in @ASSUMPTIONS.md@ at the repository root.
defaultInput :: PlanInput
defaultInput = PlanInput
  { currentAge                  = 32
  , retirementAge               = 60
  , lifeExpectancy              = 85
  , currentMonthlyExpense       = 60000
  , currentCorpus               = 1500000
  , monthlyInvestment           = 30000
  , annualStepUpPercent         = 5
  , inflationPercent            = 6
  , preRetirementReturnPercent  = 11
  , postRetirementReturnPercent = 7
  , expenseAdjustmentPercent    = 0
  , otherMonthlyIncome          = 0
  , safeWithdrawalRatePercent   = 3.25
    -- A retired couple: about Rs.1 lakh of premiums for a base policy plus a
    -- super top-up, and about Rs.50,000 that insurance does not pay.
  , healthcareAnnualToday       = 150000
    -- Aon 11.5%, WTW 12.9% and Mercer 9.9% for 2026 are all employer
    -- group-plan trends; 10% is the middle of the range, and it tapers.
  , medicalInflationPercent     = 10
    -- Premiums step up 15-25% per five-year age band: roughly 3-5% a year.
    -- 2.5% is the cautious end once insurer caps on senior hikes are allowed for.
  , healthcareAgeingPercent     = 2.5
  , taxMode                     = EstimateFromSlabs
  , flatTaxRatePercent          = 10
  , equitySharePercent          = 60
  }

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

-- | How well placed the user is, as a small closed set rather than free text.
--
-- The frontend maps each constructor to a colour and a message, so the
-- backend never has to know anything about presentation.  The bands
-- themselves are defined in 'Calculator.verdictFor'.
data Verdict
  = Comfortable    -- ^ Projected corpus comfortably exceeds the requirement.
  | OnTrack        -- ^ Projected corpus is within touching distance either way.
  | SlightlyBehind -- ^ A real but closeable shortfall.
  | Lagging        -- ^ A large shortfall needing a change of plan.
  deriving (Show, Eq, Generic)

instance ToJSON Verdict

-- | One year of the accumulation phase (today up to the retirement date).
--
-- These rows are what the "corpus growth" chart is drawn from, and they also
-- serve as an audit trail: anyone can check that
-- @closingCorpus == openingCorpus + contribution + growth@ for every row.
data AccumulationRow = AccumulationRow
  { accYear          :: Int     -- ^ 0 = today, 1 = one year from now, …
  , accAge           :: Double  -- ^ Age at the /end/ of this year.
  , accOpeningCorpus :: Rupees
  , accContribution  :: Rupees  -- ^ Total invested during the year (12 months).
  , accGrowth        :: Rupees  -- ^ Investment returns earned during the year.
  , accClosingCorpus :: Rupees
  , accTargetCorpus  :: Rupees
    -- ^ Where the corpus /would need/ to be at this age to stay on a straight
    -- path to the goal.  Drawn as the second line on the chart so the user can
    -- see the gap opening or closing, not just the final number.
  } deriving (Show, Generic)

instance ToJSON AccumulationRow where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

-- | One year of the drawdown phase (retirement date to life expectancy).
data DrawdownRow = DrawdownRow
  { drwYear          :: Int     -- ^ 1 = first year of retirement.
  , drwAge           :: Double  -- ^ Age at the /start/ of this year.
  , drwOpeningCorpus :: Rupees
  , drwWithdrawal    :: Rupees
    -- ^ Gross amount taken at the start of the year — spending plus the tax on
    -- the withdrawal itself.  Capped at the balance once the money runs out.
  , drwLivingCost    :: Rupees  -- ^ Everyday spending the corpus covers this year.
  , drwHealthcareCost :: Rupees -- ^ Healthcare the corpus covers this year.
  , drwTax           :: Rupees
    -- ^ Tax paid out of the corpus this year: the year's tax less whatever
    -- part of it surplus other income covered.
  , drwLivingReal    :: Rupees
  , drwHealthcareReal :: Rupees
  , drwTaxReal       :: Rupees
    -- ^ The three costs above in __today's__ rupees, for the stacked chart.
  , drwHealthcareShare :: Double
    -- ^ Healthcare as a percentage of the year's total spending.
  , drwGainFraction  :: Double
    -- ^ Share of each rupee withdrawn that is investment gain, as a
    -- percentage.  Only gains are taxed, and this share rises as the
    -- original money is spent first.
  , drwGrowth        :: Rupees  -- ^ Earned on the balance left after withdrawing.
  , drwClosingCorpus :: Rupees  -- ^ Floored at zero — the corpus cannot go negative.
  , drwClosingReal   :: Rupees
    -- ^ The same closing balance, discounted back into __today's__ rupees.
    --
    -- This field exists because the nominal figure is actively misleading.
    -- With returns above the withdrawal rate the nominal corpus /grows/
    -- throughout retirement, so a chart of it appears to show the retiree
    -- getting richer and richer — while their expenses have been inflating
    -- just as fast. In today's money the same plan shows the corpus being
    -- steadily drawn down, which is what is actually happening. Charts on the
    -- results page plot this column, not the nominal one.
  } deriving (Show, Generic)

instance ToJSON DrawdownRow where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

-- | The headline numbers — everything the user reads before looking at a chart.
data Summary = Summary
  { yearsToRetirement        :: Double
  , yearsInRetirement        :: Double

    -- Expenses
  , monthlyExpenseAtRetirement :: Rupees
    -- ^ First-year-of-retirement monthly spending, in future rupees.
  , annualExpenseAtRetirement  :: Rupees
  , annualNeedFromCorpus       :: Rupees
    -- ^ First-year living costs plus healthcare, less any
    -- 'otherMonthlyIncome'.  The spending the corpus has to fund in year one,
    -- before tax.
  , healthcareAtRetirement     :: Rupees
    -- ^ First-year-of-retirement healthcare cost, in future rupees.
  , healthcareMonthlyAtRetirement :: Rupees
    -- ^ The same, per month, so it can sit beside 'monthlyExpenseAtRetirement'
    -- without mixing a monthly figure with a yearly one.
  , grossFirstYearWithdrawal   :: Rupees
    -- ^ 'annualNeedFromCorpus' plus the tax on withdrawing it.
  , firstYearTaxRate           :: Double
    -- ^ First year's tax as a percentage of the gross withdrawal.
  , averageTaxRate             :: Double
    -- ^ Tax as a percentage of everything withdrawn over the whole retirement.
  , healthcareShareAtRetirement :: Double
  , healthcareShareAt75        :: Maybe Double
    -- ^ 'Nothing' if 75 falls outside the retirement years.
  , healthcareShareAtEnd       :: Double
    -- ^ Healthcare as a percentage of spending at three points in retirement.

    -- What healthcare and tax add to the target.  These three sum to
    -- 'requiredCorpus'.  Each is the extra corpus the item demands when it is
    -- switched on after the ones before it: living costs alone, then plus
    -- healthcare, then plus tax.
  , requiredForLiving          :: Rupees
  , requiredForHealthcare      :: Rupees
  , requiredForTax             :: Rupees

    -- The two numbers everything hinges on
  , requiredCorpus           :: Rupees
    -- ^ The headline target: the __larger__ of the two methods below.
  , requiredCorpusDepletion  :: Rupees
    -- ^ Method 1 — fund an inflating withdrawal stream and finish at exactly
    -- zero on the day you die.
  , requiredCorpusSwr        :: Rupees
    -- ^ Method 2 — hold enough that a safe withdrawal rate covers the first
    -- year's expenses, leaving the corpus intact in real terms.
  , requiredCorpusMethod     :: Text
    -- ^ Which of the two won, so the frontend can say so plainly.
  , projectedCorpus          :: Rupees
  , surplusOrGap             :: Rupees
    -- ^ Positive = surplus, negative = shortfall.
  , fundedRatio              :: Double
    -- ^ @projectedCorpus / requiredCorpus@.  1.0 means exactly on target.
  , verdict                  :: Verdict
  , verdictMessage           :: Text

    -- What to do about it
  , requiredMonthlyInvestment   :: Rupees
    -- ^ The monthly SIP that would exactly hit the target, at the same step-up.
  , additionalMonthlyInvestment :: Rupees
    -- ^ How much more per month than the user is investing today.  Zero if
    -- already on track.
  , fundedGapPercent            :: Double
    -- ^ How far the projection is from the target, signed: @-28@ means 28%
    -- short, @+3@ means 3% ahead.  Just 'fundedRatio' restated, because "28%
    -- behind" is what people actually ask.
  , monthlyInvestmentChange     :: Rupees
    -- ^ 'requiredMonthlyInvestment' minus what is invested today, signed.
    -- Positive: invest this much more a month.  Negative: the target would be
    -- hit even investing this much less.
  , monthlyInvestmentChangePercent :: Maybe Double
    -- ^ The same change as a percentage of today's monthly investment.
    -- 'Nothing' when nothing is invested today, since there is no base.
    --
    -- This is deliberately /not/ equal to 'fundedGapPercent'.  Being 28% short
    -- of the corpus does not mean investing 28% more: savings already held
    -- keep compounding whatever you do, so the future investments have to
    -- cover the whole gap on their own — and do it alongside the step-up.

    -- Context for the reader
  , requiredCorpusInTodaysRupees  :: Rupees
  , projectedCorpusInTodaysRupees :: Rupees
    -- ^ Both corpora discounted back to today's purchasing power, because
    -- "₹12 crore" is impossible to judge without knowing what it buys.
  , corpusMultipleRequired   :: Double
    -- ^ @requiredCorpus / annualNeedFromCorpus@ — the familiar "25× annual
    -- expenses" rule of thumb, recomputed from this user's actual numbers.
    -- For Indian assumptions this should land around 28–33; the American 25×
    -- is generally too thin.
  , corpusMultipleDepletion  :: Double
    -- ^ The same multiple implied by the depletion method alone, which is
    -- always the smaller of the two.
  , realReturnPreRetirement  :: Double
    -- ^ Inflation-adjusted return while accumulating, as a percentage.
  , realReturnPostRetirement :: Double
    -- ^ Inflation-adjusted return during retirement, as a percentage.
  , impliedWithdrawalRate    :: Double
    -- ^ First year's gross withdrawal (tax included) as a percentage of the
    -- __projected__ corpus —
    -- i.e. the withdrawal rate this plan would actually force on you, as
    -- opposed to the one assumed in 'safeWithdrawalRatePercent'.  If this
    -- comes out above roughly 3.5% the plan is leaning on optimism.
  , corpusLastsUntilAge      :: Maybe Double
    -- ^ Age at which the /projected/ corpus is exhausted.  'Nothing' means it
    -- survives past 'lifeExpectancy', which is the outcome you want.

    -- Where the projected corpus comes from
  , fvOfCurrentCorpus        :: Rupees
  , fvOfFutureInvestments    :: Rupees
    -- ^ These two sum to 'projectedCorpus'.  Splitting them out shows how much
    -- of the outcome is already locked in versus still depending on future
    -- discipline.
  } deriving (Show, Generic)

instance ToJSON Summary where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

-- | The complete response: headline numbers plus both year-by-year schedules.
data PlanResult = PlanResult
  { summary      :: Summary
  , accumulation :: [AccumulationRow]
  , drawdown     :: [DrawdownRow]
  , echoedInput  :: PlanInput
    -- ^ The input is echoed back so the frontend can label charts with the
    -- exact assumptions that produced them.
  } deriving (Show, Generic)

instance ToJSON PlanResult where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

-- | A rejected input, with a message aimed at the person who typed it.
newtype CalcError = CalcError { errorMessage :: Text }
  deriving (Show, Generic)

instance ToJSON CalcError where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

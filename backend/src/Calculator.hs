{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Calculator
-- Description : All of the retirement arithmetic, and nothing else.
--
-- == The model in one paragraph
--
-- Retirement planning reduces to comparing two numbers at a single moment in
-- time — the retirement date.  On one side is the __required corpus__: the
-- lump sum you must have on that date to fund an inflating stream of expenses
-- until you die.  On the other is the __projected corpus__: what your existing
-- savings plus your future monthly investments will actually have grown to by
-- then.  Everything this module computes is in service of those two numbers
-- and the gap between them.
--
-- == Why the phases use different rates
--
-- Before retirement the portfolio can be equity-heavy, because a crash twenty
-- years from your retirement date is an opportunity rather than a disaster.
-- After retirement it cannot, because you are selling units to eat and a crash
-- forces you to sell at the bottom.  So the two phases get separate return
-- assumptions, and the post-retirement one is always the lower of the two.
--
-- == Conventions used throughout
--
-- * Rates are 'Rate' values (decimal fractions), never bare percentages.
-- * Money is in rupees, never lakhs or crores.
-- * The accumulation phase is modelled __year by year__, with the twelve
--   monthly SIPs inside each year handled at a monthly rate.  Annual steps
--   keep the schedule readable and chartable; the monthly inner loop keeps it
--   accurate.
-- * Withdrawals in retirement happen at the __start__ of each year, because
--   you need the year's money before you can spend it.  This is the
--   conservative convention and it is what makes the required corpus an
--   annuity-/due/ rather than an ordinary annuity.
module Calculator
  ( calculate
  , selfChecks
    -- * Exposed for testing and for reading
  , realRate
  , monthlyRate
  , compoundFor
  , pvOfInflatingWithdrawals
  , fvOfOneYearOfSips
  ) where

import           Data.List  (find)
import           Data.Maybe (isNothing)
import qualified Data.Text  as T
import           Tax
import           Types

--------------------------------------------------------------------------------
-- Numerical helpers
--------------------------------------------------------------------------------

-- | Tolerance for "is this rate effectively zero".
--
-- Several closed-form annuity formulas divide by the rate, so the zero case
-- has to be branched on rather than hoped about.
epsilon :: Double
epsilon = 1e-9

-- | Grow a lump sum at a compound annual rate for a whole number of years.
--
-- > compoundFor (ratePercent 10) 10 100000  ==  259374.25…
--
-- This is the plain compound interest formula, @P × (1 + r)ⁿ@.  It is used for
-- two quite different jobs: growing money forward (an existing corpus to the
-- retirement date) and growing /prices/ forward (today's expenses to the
-- retirement date).  Inflation is just compound interest working against you.
compoundFor :: Rate -> Int -> Double -> Double
compoundFor r years p = p * growthFactor r ^^ years

-- | The __real__ (inflation-adjusted) rate of return, via the Fisher equation.
--
-- > realRate nominal inflation = (1 + nominal) / (1 + inflation) - 1
--
-- This is the one formula most spreadsheets get wrong.  The tempting shortcut
-- is @nominal - inflation@, and for small numbers it is nearly right: at 7%
-- returns and 6% inflation the shortcut gives 1.00% and the correct formula
-- gives 0.9434%.  But the error grows with the size of the rates, and it
-- always errs in the optimistic direction — it makes your money look like it
-- stretches further than it does.  We use the exact form everywhere.
--
-- Working in real terms is what lets the required-corpus calculation ignore
-- inflation entirely: if withdrawals grow at inflation /and/ the corpus grows
-- at the nominal rate, then in today's-rupees terms the withdrawals are flat
-- and the corpus grows at the real rate.  A growing annuity collapses into a
-- level one.
realRate :: Rate -> Rate -> Rate
realRate nominal inflation =
  Rate (growthFactor nominal / growthFactor inflation - 1)

-- | The effective __monthly__ rate implied by an effective __annual__ rate.
--
-- > monthlyRate (Rate 0.12) = Rate 0.0094888…   (not 0.01)
--
-- Note the twelfth root rather than a division by twelve.  Dividing by twelve
-- treats the input as a /nominal/ rate compounded monthly, which quietly
-- inflates a stated 12% into an effective 12.68%.  Mutual fund returns in
-- India are quoted as CAGR — an effective annual figure — so the twelfth root
-- is the consistent reading.  (This makes our SIP numbers land roughly 3–4%
-- below the popular Indian SIP calculators, which use the division; the
-- divergence is deliberate and is documented in @ASSUMPTIONS.md@.)
monthlyRate :: Rate -> Rate
monthlyRate r = Rate (growthFactor r ** (1 / 12) - 1)

-- | What one year of monthly SIPs is worth at the __end__ of that year.
--
-- The twelve instalments are treated as arriving at the /start/ of each month
-- (an annuity-due), which is how a SIP mandate actually behaves — the bank
-- debits you on the 1st and the units are allotted immediately.  So the first
-- instalment earns twelve months of growth, the last earns one.
--
-- > fvOfOneYearOfSips (ratePercent 11) 1  ==  12.7038…
--
-- That is, ₹1 invested monthly for a year becomes ₹12.70 rather than ₹12 —
-- the ₹0.70 is the growth the instalments earned on their way through the
-- year.  Ignoring this (just adding up the twelve instalments and compounding
-- from the year end) understates the final corpus by several percent over a
-- long horizon, which is exactly the sort of quiet error this calculator is
-- trying to avoid.
fvOfOneYearOfSips :: Rate -> Rupees -> Rupees
fvOfOneYearOfSips annual monthly
  | abs rm < epsilon = monthly * 12          -- zero return: just the instalments
  | otherwise        = monthly * annuityDueFactor
  where
    Rate rm          = monthlyRate annual
    -- ((1+rm)^12 - 1) / rm  is the ordinary-annuity factor (payments at month
    -- end); multiplying by (1+rm) shifts every payment one month earlier,
    -- turning it into an annuity-due.
    annuityDueFactor = ((1 + rm) ^^ (12 :: Int) - 1) / rm * (1 + rm)

-- | The lump sum needed today to fund @n@ yearly withdrawals that grow with
-- inflation, given a portfolio earning @nominal@.
--
-- This is the __required corpus__ formula, and it is the heart of the whole
-- calculator.  The trick is to do the arithmetic in real terms:
--
-- 1. Convert the nominal return into a real return against inflation.
-- 2. Because withdrawals grow at exactly inflation, in real terms they are
--    /constant/ — so the growing annuity becomes a level annuity.
-- 3. Take the present value of @n@ level withdrawals at the real rate, with
--    the first one due immediately (an annuity-due, because you withdraw the
--    first year's money on the day you retire).
--
-- > PV = W × (1 − (1 + rr)⁻ⁿ) / rr × (1 + rr)
--
-- The @rr ≈ 0@ branch matters in practice, not just in theory: a 6% portfolio
-- against 6% inflation is a perfectly ordinary conservative Indian scenario,
-- and there the answer is simply @W × n@ — you need exactly as many years of
-- expenses as you have years to live, because the portfolio is doing nothing
-- but keeping pace with prices.
--
-- A negative real rate (returns below inflation) is handled by the same
-- formula without special-casing, and correctly demands /more/ than @W × n@.
pvOfInflatingWithdrawals
  :: Rate    -- ^ nominal post-retirement return
  -> Rate    -- ^ inflation
  -> Int     -- ^ number of years the money must last
  -> Rupees  -- ^ first year's withdrawal, in retirement-date rupees
  -> Rupees
pvOfInflatingWithdrawals nominal inflation n firstWithdrawal
  | n <= 0            = 0
  | abs rr < epsilon  = firstWithdrawal * fromIntegral n
  | otherwise         = firstWithdrawal * levelFactor * (1 + rr)
  where
    Rate rr     = realRate nominal inflation
    levelFactor = (1 - (1 + rr) ** negate (fromIntegral n)) / rr

-- | The corpus implied by a safe withdrawal rate: @W / swr@.
--
-- Where 'pvOfInflatingWithdrawals' asks "what exactly runs out on schedule",
-- this asks "what is large enough that I never have to care about the
-- schedule".  Dividing one year's spending by 3.25% is the same as holding
-- about 31× annual expenses.
--
-- The American version of this rule uses 4% (25×), and it does not survive
-- the journey to India.  Published Indian work — Saraogi's application of
-- Bengen's method to Indian data, and Basunivesh's Monte Carlo on a 50:50
-- Nifty TRI / G-Sec portfolio — lands at 3–3.5%.  In that Monte Carlo a 3.5%
-- withdrawal survived 30 years in 89.9% of simulated paths while 4% survived
-- only 77.7%, which is a failure rate no one should accept for the one
-- outcome they cannot retake.
corpusForWithdrawalRate
  :: Rate    -- ^ safe withdrawal rate
  -> Rupees  -- ^ first year's withdrawal need
  -> Rupees
corpusForWithdrawalRate (Rate swr) need
  | swr < epsilon = 0
  | otherwise     = need / swr

--------------------------------------------------------------------------------
-- The accumulation phase
--------------------------------------------------------------------------------

-- | Roll a corpus forward one year at a time, from today to the retirement date.
--
-- Returns @(opening, contribution, growth, closing)@ for each year, so that
-- the identity @closing == opening + contribution + growth@ can be checked on
-- every single row.  That identity is the reason the growth figure is split
-- into two parts internally rather than computed as a residual — a residual
-- would make the identity true by construction even if the maths were wrong.
projectCorpus
  :: Int     -- ^ number of years to project
  -> Rate    -- ^ nominal annual return while accumulating
  -> Rate    -- ^ annual step-up applied to the monthly investment
  -> Rupees  -- ^ corpus held today
  -> Rupees  -- ^ monthly investment in year 1
  -> [(Rupees, Rupees, Rupees, Rupees)]
projectCorpus years r stepUp opening firstYearMonthly = go 1 opening
  where
    go year balance
      | year > years = []
      | otherwise    = (balance, contribution, growth, closing) : go (year + 1) closing
      where
        -- The step-up applies from year 2 onwards, so year 1 uses the amount
        -- the user actually typed in.
        monthly       = firstYearMonthly * growthFactor stepUp ^^ (year - 1)
        contribution  = monthly * 12

        -- Growth has two distinct sources, and keeping them apart is what
        -- makes this auditable:
        --   1. the balance carried in from last year, invested all year;
        balanceGrowth = balance * unRate r
        --   2. this year's own instalments, each invested for only part of
        --      the year.
        sipGrowth     = fvOfOneYearOfSips r monthly - contribution

        growth        = balanceGrowth + sipGrowth
        closing       = balance + contribution + growth

-- | The future value of __one rupee__ invested monthly, stepped up annually.
--
-- The whole accumulation is linear in the monthly investment amount: doubling
-- the SIP exactly doubles the part of the corpus that the SIP produced.  That
-- linearity is what lets 'requiredMonthlyFor' solve for the needed SIP in
-- closed form instead of searching for it numerically — no solver, no
-- iteration, no convergence tolerance to get wrong.
fvPerRupeeOfSip :: Int -> Rate -> Rate -> Double
fvPerRupeeOfSip years r stepUp =
  case projectCorpus years r stepUp 0 1 of
    [] -> 0
    xs -> let (_, _, _, closing) = last xs in closing

-- | The monthly investment that would exactly hit the required corpus.
--
-- Rearranges @projected = fvOfExistingCorpus + monthly × fvPerRupee@ for
-- @monthly@.  Floored at zero: if the existing corpus alone already overshoots
-- the target, the answer is "you need invest nothing further", not a negative
-- SIP.
requiredMonthlyFor
  :: Int     -- ^ years to retirement
  -> Rate    -- ^ pre-retirement return
  -> Rate    -- ^ step-up
  -> Rupees  -- ^ future value of the corpus already held
  -> Rupees  -- ^ required corpus
  -> Rupees
requiredMonthlyFor years r stepUp fvExisting required
  | perRupee < epsilon = 0   -- no years left to invest; the question is moot
  | otherwise          = max 0 ((required - fvExisting) / perRupee)
  where
    perRupee = fvPerRupeeOfSip years r stepUp

--------------------------------------------------------------------------------
-- Healthcare
--------------------------------------------------------------------------------

-- | How many years medical inflation takes to settle to its long-run rate.
medicalTaperYears :: Int
medicalTaperYears = 20

-- | How far above general inflation medical inflation settles in the long run.
medicalLongRunPremium :: Double
medicalLongRunPremium = 0.02

-- | Medical inflation in year @s@ from today (@s = 0@ is the coming year).
--
-- The near-term rate tapers in a straight line to general inflation + 2 points
-- over 'medicalTaperYears', then stays there.
--
-- Why it has to taper: the 10–13% figures quoted for India (Aon, WTW, Mercer)
-- are employer group-plan cost trends, which bundle price rises with people
-- using more care and insurers repricing.  Held flat for fifty years they make
-- healthcare 70% of an 85-year-old's spending, which no data supports.
-- Actuaries' long-run models (the US Society of Actuaries' Getzen model) assume
-- medical trend converges towards income growth for the same reason: health
-- cannot outgrow the economy for ever.  India's CPI health index has itself
-- run only about half a point above headline CPI over the last decade.
--
-- If the near-term rate is set /below/ the long-run target, it is simply held
-- flat — a taper that climbed would surprise the person who set it.
medicalRateInYear :: Rate -> Rate -> Int -> Rate
medicalRateInYear (Rate nearTerm) (Rate general) s =
  Rate (nearTerm + (longRun - nearTerm) * progress)
  where
    longRun  = min nearTerm (general + medicalLongRunPremium)
    progress = fromIntegral (min s medicalTaperYears)
             / fromIntegral medicalTaperYears

-- | How much healthcare prices have multiplied after @t@ years from today.
medicalPriceFactor :: Rate -> Rate -> Int -> Double
medicalPriceFactor nearTerm general t =
  product [ growthFactor (medicalRateInYear nearTerm general s) | s <- [0 .. t - 1] ]

-- | How much more healthcare costs at @age@ than at @baseAge@, from getting
-- older alone — prices held still.
--
-- Applied only between 60 and 85.  Before 60 the jumps between premium age
-- bands are small; after 85 the data runs out, and a factor compounding
-- without limit would assert more than anyone knows.
ageingFactor :: Rate -> Double -> Double -> Double
ageingFactor ageing baseAge age =
  growthFactor ageing ** (band age - band baseAge)
  where
    band x = min 85 (max 60 x)

--------------------------------------------------------------------------------
-- The drawdown phase
--------------------------------------------------------------------------------

-- | Tax treatment of withdrawals, with percentages already turned into
-- fractions.
data TaxTreatment
  = Untaxed
  | Flat Double    -- ^ tax as a fraction of each rupee withdrawn
  | Slabs Double   -- ^ new-regime slabs; the equity share of the corpus, 0–1

-- | Everything about retirement that does not depend on how big the corpus is.
--
-- Keeping this separate from the corpus is what lets the same year-by-year
-- engine answer both "how much do I need" (solve for the corpus) and "what
-- happens to what I will have" (run it from the projected corpus).
data Retirement = Retirement
  { rtYearsToRet       :: Int
  , rtYearsInRet       :: Int
  , rtRetirementAge    :: Double
  , rtInflation        :: Rate
  , rtReturn           :: Rate     -- ^ nominal, after retiring
  , rtSwr              :: Rate
  , rtLivingAtRet      :: Rupees   -- ^ first year's living costs, future rupees
  , rtOtherIncomeToday :: Rupees   -- ^ per year, today's rupees
  , rtHealthcareToday  :: Rupees   -- ^ per year, today's rupees
  , rtMedicalNearTerm  :: Rate
  , rtAgeing           :: Rate
  , rtTax              :: TaxTreatment
  }

-- | What one year of retirement costs, before any question of tax.
data YearNeed = YearNeed
  { ynYear             :: Int     -- ^ 1 = first year of retirement
  , ynAge              :: Double
  , ynDeflator         :: Double  -- ^ divide by this to get today's rupees
  , ynLiving           :: Rupees
  , ynHealthcare       :: Rupees
  , ynOtherIncome      :: Rupees
  , ynLivingFromCorpus :: Rupees
  , ynHealthFromCorpus :: Rupees
  }

-- | The spending the corpus must fund this year, before tax.
ynNeed :: YearNeed -> Rupees
ynNeed y = ynLivingFromCorpus y + ynHealthFromCorpus y

-- | The cost of every year of retirement, in that year's rupees.
--
-- Living costs grow at general inflation from the retirement date.
-- Healthcare grows from __today__ at the tapering medical rate, and on top of
-- that with age — so a 32-year-old's healthcare figure compounds for 28 years
-- before they even retire, which is exactly why it ends up so large.
--
-- Other income (rent, a pension) pays for living costs first and healthcare
-- only with whatever is left.  The order does not change the total, only which
-- band of the chart the income is shown against.
yearNeeds :: Retirement -> [YearNeed]
yearNeeds rt = map year [1 .. rtYearsInRet rt]
  where
    gi = growthFactor (rtInflation rt)
    year k =
      let t         = rtYearsToRet rt + k - 1
          age       = rtRetirementAge rt + fromIntegral (k - 1)
          living    = rtLivingAtRet rt * gi ^^ (k - 1)
          health    = rtHealthcareToday rt
                    * medicalPriceFactor (rtMedicalNearTerm rt) (rtInflation rt) t
                    * ageingFactor (rtAgeing rt) (rtRetirementAge rt) age
          other     = rtOtherIncomeToday rt * gi ^^ t
          livingFC  = max 0 (living - other)
          healthFC  = max 0 (health - max 0 (other - living))
      in YearNeed
           { ynYear             = k
           , ynAge              = age
           , ynDeflator         = gi ^^ t
           , ynLiving           = living
           , ynHealthcare       = health
           , ynOtherIncome      = other
           , ynLivingFromCorpus = livingFC
           , ynHealthFromCorpus = healthFC
           }

-- | The gross withdrawal that leaves this year's need to spend after tax.
--
-- @gainFraction@ is the share of each rupee withdrawn that is investment gain,
-- the only part that is taxed.  Slab tax is worked out in today's rupees
-- against today's slabs (see "Tax" for why), then inflated back.
--
-- Slab tax is handed total spending and other income separately, not the
-- already-netted need: income above spending must be able to pay its own tax
-- (see 'grossUpForSlabTax').  The flat and untaxed modes do not tax other
-- income, so for them the netted need is already the whole story.
grossNeed :: TaxTreatment -> Double -> YearNeed -> Rupees
grossNeed treatment gainFraction y = case treatment of
  Untaxed      -> need
  Flat t       -> need / (1 - t)
  Slabs equity -> d * grossUpForSlabTax equity gainFraction
                                        (ynOtherIncome y / d) (spending / d)
  where
    need     = ynNeed y
    spending = ynLiving y + ynHealthcare y
    d        = ynDeflator y

-- | One simulated year of retirement.
data SimYear = SimYear
  { syNeed         :: YearNeed
  , syOpening      :: Rupees
  , syGainFraction :: Double
  , syGross        :: Rupees  -- ^ what the year calls for, tax included
  , syWithdrawal   :: Rupees  -- ^ what was actually taken
  , syGrowth       :: Rupees
  , syClosing      :: Rupees
  }

-- | Spend a corpus down year by year.
--
-- Each year: work out the gain fraction, withdraw the year's gross need at the
-- start, and let the rest grow.  Alongside the balance the engine tracks its
-- __cost basis__ — the rupees originally put in.  Growth adds to the balance
-- but not to the basis, and each withdrawal takes basis in proportion
-- (average cost), so the gain fraction @1 − basis / balance@ rises through
-- retirement as the original money is spent and the gains are left.  Indian
-- funds actually redeem first-in-first-out, which taxes a little more in the
-- early years; average cost is the documented simplification.
--
-- With @capped@ the withdrawal is limited to the balance and the balance is
-- floored at zero, which is what the chart shows.  Without it the balance may
-- go negative, which is what the solver for the required corpus needs: a
-- smooth function of the starting corpus that crosses zero exactly once.
simulate :: Bool -> Retirement -> Double -> Rupees -> [SimYear]
simulate capped rt basisRatio start = go (yearNeeds rt) start (start * basisRatio)
  where
    r = unRate (rtReturn rt)
    go [] _ _ = []
    go (y : rest) balance basis = row : go rest closing basis'
      where
        gainFraction
          | balance > epsilon = max 0 (min 1 (1 - basis / balance))
          | otherwise         = 1
        gross      = grossNeed (rtTax rt) gainFraction y
        withdrawal = if capped then max 0 (min balance gross) else gross
        basis'
          | balance > epsilon = basis * (1 - min 1 (withdrawal / balance))
          | otherwise         = basis
        remaining  = balance - withdrawal
        growth     = remaining * r
        closing    = if capped then max 0 (remaining + growth) else remaining + growth
        row = SimYear
          { syNeed         = y
          , syOpening      = balance
          , syGainFraction = gainFraction
          , syGross        = gross
          , syWithdrawal   = withdrawal
          , syGrowth       = growth
          , syClosing      = closing
          }

-- | The required corpus by both methods: @(depletion, safe withdrawal rate)@.
--
-- __Depletion__ — the corpus that runs out exactly at the planning age.
-- Without slab tax every year's withdrawal is fixed in advance, so this is the
-- present value of the withdrawals at the post-retirement return.  With
-- healthcare at zero and no tax that sum is exactly
-- 'pvOfInflatingWithdrawals' (a self-check holds it to that).  With slab tax
-- each year's tax depends on the gain fraction, which depends on the corpus,
-- so the corpus is found by bisection on the simulated end balance instead.
--
-- __Safe withdrawal rate__ — the first year's gross withdrawal divided by the
-- rate.  This method assumes spending is flat in real terms, which healthcare
-- breaks: it keeps rising faster than prices.  So with healthcare switched on
-- this method tends to understate, and the depletion figure — which does see
-- the rise — usually becomes the larger of the two.
requiredCorpora :: Retirement -> Double -> (Rupees, Rupees)
requiredCorpora rt basisRatio = (depletion, swrCorpus)
  where
    needs  = yearNeeds rt
    gr     = growthFactor (rtReturn rt)
    firstGain = max 0 (min 1 (1 - basisRatio))

    swrCorpus = case needs of
      []      -> 0
      (y : _) -> corpusForWithdrawalRate (rtSwr rt) (grossNeed (rtTax rt) firstGain y)

    depletion = case rtTax rt of
      Slabs _ -> solveDepletion
      _       -> sum [ grossNeed (rtTax rt) firstGain y / gr ^^ (ynYear y - 1)
                     | y <- needs ]

    endBalance x = case simulate False rt basisRatio x of
      [] -> x
      ys -> syClosing (last ys)

    solveDepletion
      | endBalance 0 >= 0 = 0
      | otherwise         = bisect (0 :: Int) 0 (growUntilEnough (0 :: Int) firstGuess)

    firstGuess = max 1 (sum [ grossNeed (rtTax rt) 1 y | y <- needs ])

    growUntilEnough n hi
      | n >= 80 || endBalance hi >= 0 = hi
      | otherwise                     = growUntilEnough (n + 1) (hi * 2)

    bisect n lo hi
      | n >= 200 || hi - lo <= 1e-10 * hi = (lo + hi) / 2
      | endBalance mid >= 0               = bisect (n + 1) lo mid
      | otherwise                         = bisect (n + 1) mid hi
      where mid = (lo + hi) / 2

-- | The headline requirement: the larger of the two methods.
requiredCorpusFor :: Retirement -> Double -> Rupees
requiredCorpusFor rt basisRatio = uncurry max (requiredCorpora rt basisRatio)

-- | Turn a simulated retirement into table rows.
toDrawdownRow :: Int -> Rate -> SimYear -> DrawdownRow
toDrawdownRow yearsToRet inflation sy = DrawdownRow
  { drwYear            = ynYear y
  , drwAge             = ynAge y
  , drwOpeningCorpus   = syOpening sy
  , drwWithdrawal      = syWithdrawal sy
  , drwLivingCost      = ynLivingFromCorpus y
  , drwHealthcareCost  = ynHealthFromCorpus y
  , drwTax             = tax
  , drwLivingReal      = ynLivingFromCorpus y / d
  , drwHealthcareReal  = ynHealthFromCorpus y / d
  , drwTaxReal         = tax / d
  , drwHealthcareShare = shareOf (ynHealthcare y) (ynLiving y + ynHealthcare y)
  , drwGainFraction    = syGainFraction sy * 100
  , drwGrowth          = syGrowth sy
  , drwClosingCorpus   = syClosing sy
    -- This closing balance sits (yearsToRet + year) years from today, so that
    -- is how far it has to be discounted to be comparable with money in the
    -- user's pocket right now.
  , drwClosingReal     = syClosing sy
                           / growthFactor inflation ^^ (yearsToRet + ynYear y)
  }
  where
    y   = syNeed sy
    d   = ynDeflator y
    tax = max 0 (syGross sy - ynNeed y)

-- | @part@ as a percentage of @whole@, zero when there is no whole.
shareOf :: Double -> Double -> Double
shareOf part whole = if whole > epsilon then part / whole * 100 else 0

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

-- | Reject inputs that would make the arithmetic meaningless before it runs.
--
-- These are not style preferences — each one guards a specific way the model
-- breaks.  A retirement age below the current age inverts the accumulation
-- phase; a zero expense makes the required corpus zero and the funded ratio
-- infinite; a life expectancy at or below the retirement age leaves no years
-- to fund.
validate :: PlanInput -> Either CalcError ()
validate i = mapM_ check checks
  where
    check (ok, msg) = if ok then Right () else Left (CalcError msg)

    checks =
      [ ( currentAge i >= 15 && currentAge i <= 90
        , "Current age must be between 15 and 90." )
      , ( retirementAge i >= currentAge i + 1
        , "Retirement age must be at least one year after your current age." )
      , ( retirementAge i <= 85
        , "Retirement age must be 85 or below." )
      , ( lifeExpectancy i >= retirementAge i + 1
        , "Life expectancy must be at least one year after your retirement age." )
      , ( lifeExpectancy i <= 110
        , "Life expectancy must be 110 or below." )
      , ( currentMonthlyExpense i > 0
        , "Current monthly expense must be greater than zero." )
      , ( currentCorpus i >= 0
        , "Current corpus cannot be negative." )
      , ( monthlyInvestment i >= 0
        , "Monthly investment cannot be negative." )
      , ( otherMonthlyIncome i >= 0
        , "Other monthly income cannot be negative." )
      , ( inflationPercent i >= 0 && inflationPercent i <= 20
        , "Inflation must be between 0% and 20%." )
      , ( preRetirementReturnPercent i >= 0 && preRetirementReturnPercent i <= 30
        , "Pre-retirement return must be between 0% and 30%." )
      , ( postRetirementReturnPercent i >= 0 && postRetirementReturnPercent i <= 30
        , "Post-retirement return must be between 0% and 30%." )
      , ( annualStepUpPercent i >= 0 && annualStepUpPercent i <= 25
        , "Annual step-up must be between 0% and 25%." )
      , ( expenseAdjustmentPercent i >= (-50) && expenseAdjustmentPercent i <= 100
        , "Retirement expense adjustment must be between -50% and +100%." )
      , ( healthcareAnnualToday i >= 0 && healthcareAnnualToday i <= 5000000
        , "Healthcare per year must be between Rs.0 and Rs.50 lakh." )
      , ( medicalInflationPercent i >= 0 && medicalInflationPercent i <= 25
        , "Medical inflation must be between 0% and 25%." )
      , ( healthcareAgeingPercent i >= 0 && healthcareAgeingPercent i <= 10
        , "Healthcare cost growth from ageing must be between 0% and 10% a year." )
      , ( flatTaxRatePercent i >= 0 && flatTaxRatePercent i <= 50
        , "Flat tax rate must be between 0% and 50%." )
      , ( equitySharePercent i >= 0 && equitySharePercent i <= 100
        , "Equity share must be between 0% and 100%." )
      ]

--------------------------------------------------------------------------------
-- The verdict
--------------------------------------------------------------------------------

-- | Turn the funded ratio into one of four bands.
--
-- The bands are deliberately wide.  Every input to this calculator is a guess
-- about the next thirty years, so a projection that lands at 0.97 of the
-- target is not meaningfully different from one that lands at 1.03 — treating
-- them differently would imply a precision the model does not have.
verdictFor :: Double -> Verdict
verdictFor ratio
  | ratio >= 1.10 = Comfortable
  | ratio >= 0.95 = OnTrack
  | ratio >= 0.75 = SlightlyBehind
  | otherwise     = Lagging

-- | A sentence explaining the verdict, phrased for the person who typed the
-- numbers in rather than for a spreadsheet.
verdictText :: Verdict -> Double -> T.Text
verdictText v ratio = case v of
  Comfortable ->
    "You are comfortably ahead. On these assumptions you are projected to reach "
    <> pct <> " of the corpus you need, so you have room to retire earlier, \
       \spend more, or take less risk with your portfolio."
  OnTrack ->
    "You are on track. You are projected to reach " <> pct <> " of the corpus \
    \you need, which is as close as a thirty-year projection can honestly get. \
    \Keep the step-up going and review this once a year."
  SlightlyBehind ->
    "You are slightly behind. You are projected to reach " <> pct <> " of the \
    \corpus you need. This is a closeable gap — raising your monthly \
    \investment or working two or three years longer would likely fix it."
  Lagging ->
    "You are lagging. You are projected to reach only " <> pct <> " of the \
    \corpus you need. Closing a gap this size usually takes more than one \
    \lever: a higher monthly investment, a later retirement age, and a \
    \realistic look at post-retirement spending."
  where
    pct = T.pack (show (round (ratio * 100) :: Int)) <> "%"

--------------------------------------------------------------------------------
-- The top-level calculation
--------------------------------------------------------------------------------

-- | Run the whole plan.
--
-- The order below is the order the reasoning actually goes in, and each step
-- depends only on the ones above it:
--
-- 1. How many years are we accumulating, and how many are we spending?
-- 2. What will each year of retirement cost — living, healthcare, and tax?
-- 3. What lump sum funds that for the whole of retirement?  (required)
-- 4. What will our savings and investments actually be worth?  (projected)
-- 5. Compare, and work out what would close any gap.
calculate :: PlanInput -> Either CalcError PlanResult
calculate input = do
  validate input

  let -- ---- Rates, converted from percentages exactly once, here. ----------
      inflation = ratePercent (inflationPercent i)
      preReturn = ratePercent (preRetirementReturnPercent i)
      postReturn = ratePercent (postRetirementReturnPercent i)
      stepUp    = ratePercent (annualStepUpPercent i)
      swr       = ratePercent (safeWithdrawalRatePercent i)

      -- ---- 1. The two horizons. -------------------------------------------
      yearsToRet = round (retirementAge i - currentAge i) :: Int
      yearsInRet = round (lifeExpectancy i - retirementAge i) :: Int

      -- ---- 2. The cost of retirement, year by year. -----------------------
      -- Today's annual living costs, carried forward through `yearsToRet`
      -- years of inflation, then adjusted for the lifestyle change retirement
      -- brings.  Healthcare is a separate stream with its own inflation; see
      -- 'yearNeeds'.
      annualExpenseToday = currentMonthlyExpense i * 12
      inflatedExpense    = compoundFor inflation yearsToRet annualExpenseToday
      lifestyleFactor    = 1 + expenseAdjustmentPercent i / 100
      expenseAtRet       = inflatedExpense * lifestyleFactor

      taxTreatment = case taxMode i of
        NoTax             -> Untaxed
        FlatRate          -> Flat (flatTaxRatePercent i / 100)
        EstimateFromSlabs -> Slabs (equitySharePercent i / 100)

      retirement = Retirement
        { rtYearsToRet       = yearsToRet
        , rtYearsInRet       = yearsInRet
        , rtRetirementAge    = retirementAge i
        , rtInflation        = inflation
        , rtReturn           = postReturn
        , rtSwr              = swr
        , rtLivingAtRet      = expenseAtRet
        , rtOtherIncomeToday = otherMonthlyIncome i * 12
        , rtHealthcareToday  = healthcareAnnualToday i
        , rtMedicalNearTerm  = ratePercent (medicalInflationPercent i)
        , rtAgeing           = ratePercent (healthcareAgeingPercent i)
        , rtTax              = taxTreatment
        }

      -- ---- 4 (needed early). The projected corpus. ------------------------
      -- Existing savings compound on their own; future investments are rolled
      -- forward year by year.  Keeping the two apart lets the summary show how
      -- much of the outcome is already banked versus still to be earned.
      fvExisting = compoundFor preReturn yearsToRet (currentCorpus i)
      schedule   = projectCorpus yearsToRet preReturn stepUp (currentCorpus i)
                                 (monthlyInvestment i)
      projected  = case schedule of
                     [] -> currentCorpus i      -- retiring this year
                     xs -> let (_, _, _, c) = last xs in c
      fvInvestments = projected - fvExisting

      -- How much of the corpus at retirement is money put in; see 'basisRatioOf'.
      basisRatio = basisRatioOf (currentCorpus i) schedule

      -- ---- 3. The required corpus, by two methods that disagree. ----------
      --
      -- This is the step where most calculators quietly mislead, so it is
      -- worth spelling out.  There are two defensible ways to ask "how much do
      -- I need", and they give materially different answers:
      --
      --   (a) DEPLETION.  Fund the withdrawal stream exactly, so the last
      --       rupee is spent on the day you reach your planning age.  This is
      --       the textbook annuity calculation and it is what HDFC AMC and
      --       most Indian calculators publish.  It is also optimistic: it
      --       assumes returns show up on schedule, that you die on time, and
      --       that a bad first decade of markets never happens.
      --
      --   (b) SAFE WITHDRAWAL RATE.  Hold a corpus large enough that a
      --       sustainable withdrawal rate covers year one.  This implicitly
      --       buys insurance against sequence-of-returns risk and against
      --       living longer than planned, which is why it usually asks for
      --       more — though not once healthcare is rising faster than prices,
      --       which this method cannot see (see 'requiredCorpora').
      --
      -- We report both and headline the larger, because the cost of the two
      -- errors is wildly asymmetric: over-saving means retiring with money
      -- left over, while under-saving means running out at 80 with no way
      -- back into the workforce.
      (depletionCorpus, swrCorpus) = requiredCorpora retirement basisRatio
      required        = max depletionCorpus swrCorpus
      methodUsed      = if swrCorpus >= depletionCorpus
                          then "safe withdrawal rate" :: T.Text
                          else "corpus depletion"

      -- What healthcare and tax each add, switched on one after the other.
      -- The three parts sum to `required` by construction.
      livingOnly     = requiredCorpusFor retirement { rtHealthcareToday = 0
                                                    , rtTax = Untaxed } basisRatio
      beforeTax      = requiredCorpusFor retirement { rtTax = Untaxed } basisRatio

      -- ---- 5. The comparison and the fix. ---------------------------------
      gap      = projected - required
      -- Validation forces positive living costs and at least one year of
      -- retirement, but other income can still cover everything, leaving
      -- nothing required.  A divide-by-zero in a financial summary is a
      -- silent disaster, so it is guarded.
      ratio    = if required > epsilon then projected / required else 1
      v        = verdictFor ratio

      -- The monthly investment that hits its own target.  Investing more
      -- changes how much of the final corpus is gain rather than money put
      -- in, which changes the tax, which moves the target — so the answer is
      -- a fixed point, found by iterating from the target for today's plan.
      -- Without slab tax the first step is already exact.
      sipFor target = requiredMonthlyFor yearsToRet preReturn stepUp fvExisting target
      targetWithSip m = requiredCorpusFor retirement
                          (basisRatioOf (currentCorpus i)
                             (projectCorpus yearsToRet preReturn stepUp (currentCorpus i) m))
      settle n m
        | n >= (30 :: Int) || abs (m' - m) < 0.01 = m'
        | otherwise                               = settle (n + 1) m'
        where m' = sipFor (targetWithSip m)
      requiredMonthly = settle 0 (sipFor required)
      extraMonthly    = max 0 (requiredMonthly - monthlyInvestment i)

      -- ---- Charts: the projected path, and the path of someone on track. --
      targetSchedule = projectCorpus yearsToRet preReturn stepUp (currentCorpus i)
                                     requiredMonthly
      accRows = buildAccumulationRows (currentAge i) (currentCorpus i)
                                      schedule targetSchedule

      -- ---- Charts: spending the projected corpus down. --------------------
      simYears = simulate True retirement basisRatio projected
      drawRows = map (toDrawdownRow yearsToRet inflation) simYears

      -- The first year in which the corpus could not fund the full withdrawal
      -- is the year the money ran out.
      ranOutIn   = find (\sy -> syWithdrawal sy < syGross sy - 1) simYears
      lastsUntil = fmap (ynAge . syNeed) ranOutIn

      -- ---- Year one, and the shape of retirement. -------------------------
      firstYear = case yearNeeds retirement of
                    (y : _) -> Just y
                    []      -> Nothing
      firstNeed  = maybe 0 ynNeed firstYear
      firstGross = maybe 0 (grossNeed taxTreatment (1 - basisRatio)) firstYear
      healthAtRet = maybe 0 ynHealthcare firstYear

      totalGross = sum (map syGross simYears)
      totalTax   = sum [ syGross sy - ynNeed (syNeed sy) | sy <- simYears ]

      shareIn sy = shareOf (ynHealthcare (syNeed sy))
                           (ynLiving (syNeed sy) + ynHealthcare (syNeed sy))
      shareAt75  = shareIn <$> find (\sy -> round (ynAge (syNeed sy)) == (75 :: Int)) simYears
      shareAtEnd = case simYears of
                     [] -> 0
                     xs -> shareIn (last xs)

      -- ---- Context figures for the reader. --------------------------------
      -- Discounting both corpora back to today's purchasing power, because a
      -- number like "₹12 crore" is impossible to judge on its own.
      toTodaysRupees x = x / growthFactor inflation ^^ yearsToRet

      -- "How many years of retirement spending is this corpus?" — the
      -- familiar 25x/30x framing, recomputed from the user's own numbers
      -- rather than quoted as a rule.
      multipleOf c = if firstNeed > epsilon then c / firstNeed else 0

  pure PlanResult
    { summary = Summary
        { yearsToRetirement          = fromIntegral yearsToRet
        , yearsInRetirement          = fromIntegral yearsInRet
        , monthlyExpenseAtRetirement = expenseAtRet / 12
        , annualExpenseAtRetirement  = expenseAtRet
        , annualNeedFromCorpus       = firstNeed
        , healthcareAtRetirement     = healthAtRet
        , healthcareMonthlyAtRetirement = healthAtRet / 12
        , grossFirstYearWithdrawal   = firstGross
        , firstYearTaxRate           = shareOf (firstGross - firstNeed) firstGross
        , averageTaxRate             = shareOf totalTax totalGross
        , healthcareShareAtRetirement = shareOf healthAtRet (expenseAtRet + healthAtRet)
        , healthcareShareAt75        = shareAt75
        , healthcareShareAtEnd       = shareAtEnd
        , requiredForLiving          = livingOnly
        , requiredForHealthcare      = beforeTax - livingOnly
        , requiredForTax             = required - beforeTax
        , requiredCorpus             = required
        , requiredCorpusDepletion    = depletionCorpus
        , requiredCorpusSwr          = swrCorpus
        , requiredCorpusMethod       = methodUsed
        , projectedCorpus            = projected
        , surplusOrGap               = gap
        , fundedRatio                = ratio
        , verdict                    = v
        , verdictMessage             = verdictText v ratio
        , requiredMonthlyInvestment   = requiredMonthly
        , additionalMonthlyInvestment = extraMonthly
        , fundedGapPercent           = (ratio - 1) * 100
        , monthlyInvestmentChange    = requiredMonthly - monthlyInvestment i
        , monthlyInvestmentChangePercent =
            if monthlyInvestment i > epsilon
              then Just ((requiredMonthly - monthlyInvestment i) / monthlyInvestment i * 100)
              else Nothing
        , requiredCorpusInTodaysRupees  = toTodaysRupees required
        , projectedCorpusInTodaysRupees = toTodaysRupees projected
        , corpusMultipleRequired     = multipleOf required
        , corpusMultipleDepletion    = multipleOf depletionCorpus
        , realReturnPreRetirement    = unRate (realRate preReturn inflation) * 100
        , realReturnPostRetirement   = unRate (realRate postReturn inflation) * 100
        , impliedWithdrawalRate      = shareOf firstGross projected
        , corpusLastsUntilAge        = lastsUntil
        , fvOfCurrentCorpus          = fvExisting
        , fvOfFutureInvestments      = fvInvestments
        }
    , accumulation = accRows
    , drawdown     = drawRows
    , echoedInput  = i
    }
  where
    i = input

-- | The share of the corpus at retirement that is money put in rather than
-- growth.  Tax falls only on the growth, so this is where the tax calculation
-- starts.  Today's savings are counted as all money put in, because their
-- history is unknown; that understates tax a little.
basisRatioOf :: Rupees -> [(Rupees, Rupees, Rupees, Rupees)] -> Double
basisRatioOf corpusToday schedule
  | finalCorpus > epsilon = min 1 (costBasis / finalCorpus)
  | otherwise             = 1
  where
    costBasis   = corpusToday + sum [ c | (_, c, _, _) <- schedule ]
    finalCorpus = case schedule of
                    [] -> corpusToday
                    xs -> let (_, _, _, c) = last xs in c

-- | Stitch the projected and on-track schedules into chart-ready rows.
--
-- A year-zero row is prepended so both lines start from the corpus the user
-- actually holds today, rather than appearing to spring out of the axis.
buildAccumulationRows
  :: Double                                      -- ^ current age
  -> Rupees                                      -- ^ corpus today
  -> [(Rupees, Rupees, Rupees, Rupees)]          -- ^ projected schedule
  -> [(Rupees, Rupees, Rupees, Rupees)]          -- ^ on-track schedule
  -> [AccumulationRow]
buildAccumulationRows age0 corpus0 projectedRows targetRows = yearZero : rest
  where
    yearZero = AccumulationRow
      { accYear          = 0
      , accAge           = age0
      , accOpeningCorpus = corpus0
      , accContribution  = 0
      , accGrowth        = 0
      , accClosingCorpus = corpus0
      , accTargetCorpus  = corpus0
      }

    rest =
      [ AccumulationRow
          { accYear          = n
          , accAge           = age0 + fromIntegral n
          , accOpeningCorpus = opening
          , accContribution  = contribution
          , accGrowth        = growth
          , accClosingCorpus = closing
          , accTargetCorpus  = targetClosing
          }
      | (n, (opening, contribution, growth, closing), (_, _, _, targetClosing))
          <- zip3 [1 ..] projectedRows targetRows
      ]


--------------------------------------------------------------------------------
-- Self-checks
--------------------------------------------------------------------------------

-- | Internal consistency checks, run once at start-up and printed to the log.
--
-- These are not unit tests of the kind that pin down a golden number — they
-- are the structural identities the model has to satisfy to be coherent at
-- all.  If any of them fails, the formulas disagree with each other and every
-- answer the server gives is suspect, so it is worth paying a few
-- milliseconds at boot to find out.
selfChecks :: [(String, Bool)]
selfChecks =
  [ ( "compound interest: 1,00,000 at 10% for 10 years = 2,59,374"
    , closeTo 1 (compoundFor (ratePercent 10) 10 100000) 259374.246 )

  , ( "real rate uses Fisher, not subtraction: 7% vs 6% = 0.9434%, not 1%"
    , closeTo 1e-6 (unRate (realRate (ratePercent 7) (ratePercent 6))) 0.0094339 )

  , ( "one year of Rs.1 monthly SIP at 11% is worth Rs.12.70, not Rs.12"
    , closeTo 1e-3 (fvOfOneYearOfSips (ratePercent 11) 1) 12.7038 )

  , ( "zero real return means the corpus is exactly N years of expenses"
    , closeTo 1e-6 (pvOfInflatingWithdrawals (ratePercent 6) (ratePercent 6) 25 100000)
                   2500000 )

  , ( "depletion corpus lands in the familiar 18-32x band without healthcare or tax"
    , checkSummaryOf legacyInput (\s -> let m = corpusMultipleDepletion s in m > 18 && m < 32) )

  , ( "SWR corpus is exactly the reciprocal of the withdrawal rate (1/3.25% = 30.8x)"
    , checkSummary (\s -> closeTo 1e-6 (requiredCorpusSwr s / grossFirstYearWithdrawal s)
                                       (100 / safeWithdrawalRatePercent defaultInput)) )

  , ( "the headline requirement is the larger of the two methods"
    , checkSummary (\s -> requiredCorpus s
                            == max (requiredCorpusDepletion s) (requiredCorpusSwr s)) )

    -- An end-to-end check against figures computed independently during
    -- research, from a different direction and with different tooling.  This
    -- is the one check that would catch a self-consistent but wrong model.
  , ( "matches the independently computed reference case to within 0.5%"
    , matchesReferenceCase )

    -- The guard on the healthcare-and-tax change: switch both off and the
    -- year-by-year engine must give exactly what the closed-form annuity
    -- formula gave before they existed.
  , ( "no healthcare and no tax reproduces the closed-form annuity exactly"
    , reproducesClosedForm )

    -- The strongest internal check available: drive the drawdown with the
    -- depletion corpus, and it must finish at (near enough) zero in the final
    -- year.  Too much left over means the formula is over-saving the user; a
    -- premature zero means it is under-saving them, which is worse.  Run with
    -- healthcare and slab tax on, so the solver is exercised too.
  , ( "spending the DEPLETION corpus leaves it exhausted at life expectancy"
    , requiredCorpusEndsAtZero )

    -- And the mirror image: invest the SIP the model prescribes, and the
    -- projection must land on the required corpus.
  , ( "investing the REQUIRED monthly amount hits the required corpus exactly"
    , prescribedSipHitsTarget )

  , ( "a plainly under-saved plan is reported as lagging, and runs out early"
    , underSavedPlanFails )

    -- Investing today's amount plus the stated change must land on the
    -- target, whether the change is an increase or a cut.
  , ( "today's SIP plus the stated monthly change hits the target, both ways"
    , and [ changeHitsTarget sip | sip <- [10000, 30000, 100000] ] )

    -- Tax engine, against figures worked by hand from the 2026-27 slabs.
  , ( "tax: Rs.12 lakh of slab income pays nothing (87A rebate)"
    , closeTo 1e-6 (taxOnYear (TaxableYear 1200000 0)) 0 )

  , ( "tax: Rs.12.5 lakh pays Rs.52,000, not Rs.70,200 (marginal relief)"
    , closeTo 1e-6 (taxOnYear (TaxableYear 1250000 0)) 52000 )

  , ( "tax: Rs.16 lakh pays Rs.1,24,800 (20k + 40k + 60k, plus 4% cess)"
    , closeTo 1e-6 (taxOnYear (TaxableYear 1600000 0)) 124800 )

  , ( "tax: Rs.10 lakh of equity gains alone pays Rs.61,750 (after 1.25L + 4L)"
    , closeTo 1e-6 (taxOnYear (TaxableYear 0 1000000)) 61750 )

  , ( "tax: withdrawal + other income - tax = spending, in every case"
    , grossUpRoundTrips )

  , ( "tax: income that covers spending and its own tax needs no corpus"
    , surplusIncomePaysItsOwnTax )

  , ( "tax: a surplus too small for its own tax leaves only the rest to savings"
    , partialSurplusFundsOnlyTheRest )

  , ( "healthcare grows as a share of spending through retirement"
    , checkSummary (\s -> healthcareShareAtEnd s > healthcareShareAtRetirement s) )

  , ( "medical inflation settles at general inflation + 2 points after the taper"
    , closeTo 1e-12 (unRate (medicalRateInYear (ratePercent 10) (ratePercent 6) 25)) 0.08 )

  , ( "the living / healthcare / tax parts sum to the corpus you need"
    , checkSummary (\s -> closeRel 1e-9 (requiredForLiving s + requiredForHealthcare s
                                           + requiredForTax s)
                                        (requiredCorpus s)) )

  , ( "more healthcare, or a higher tax rate, never lowers the requirement"
    , requirementIsMonotonic )
  ]
  where
    closeTo tol actual expected = abs (actual - expected) <= tol

    -- Relative tolerance, for comparisons between large rupee amounts where an
    -- absolute tolerance would be meaningless.
    closeRel tol actual expected =
      abs (actual - expected) <= tol * max 1 (abs expected)

    -- The model as it stood before healthcare and tax were added.
    legacyInput = defaultInput { healthcareAnnualToday = 0, taxMode = NoTax }

    -- Run a scenario and apply a predicate to its summary.
    checkSummaryOf inp p = either (const False) (p . summary) (calculate inp)
    checkSummary = checkSummaryOf defaultInput

    -- The reference case from research: age 30 to 60, 25 years of retirement,
    -- 6% inflation, 12% pre- and 8% post-retirement returns, Rs.50,000/month
    -- of expenses today and Rs.10 lakh already saved.  The two expected
    -- figures were derived outside this program, before healthcare and tax.
    matchesReferenceCase =
      let ref = legacyInput
            { currentAge                  = 30
            , retirementAge               = 60
            , lifeExpectancy              = 85
            , currentMonthlyExpense       = 50000
            , currentCorpus               = 1000000
            , inflationPercent            = 6
            , preRetirementReturnPercent  = 12
            , postRetirementReturnPercent = 8
            }
      in checkSummaryOf ref (\s ->
           closeRel 5e-3 (requiredCorpusDepletion s) 69469000      -- Rs.6.9469 cr
           && closeRel 5e-3 (fvOfCurrentCorpus s)    29960000)     -- Rs.2.9960 cr

    reproducesClosedForm =
      checkSummaryOf legacyInput (\s ->
        let inp = legacyInput
        in closeRel 1e-9 (requiredCorpusDepletion s)
                         (pvOfInflatingWithdrawals
                            (ratePercent (postRetirementReturnPercent inp))
                            (ratePercent (inflationPercent inp))
                            (round (yearsInRetirement s))
                            (annualNeedFromCorpus s)))

    requiredCorpusEndsAtZero =
      checkSummary (\s ->
        let rows = depletionRun (requiredCorpusDepletion s)
        in case reverse rows of
             []      -> False
             (end:_) ->
               -- Every year but the last fully funded, and the leftover
               -- negligible next to one year's withdrawal.
               all (\sy -> syWithdrawal sy >= syGross sy - 1) (init rows)
               && syClosing end <= 0.01 * syWithdrawal end)

    -- The default retirement, spent down from a given starting corpus, with
    -- the same basis ratio the default projection produces.
    depletionRun start =
      let inp        = defaultInput
          inflation  = ratePercent (inflationPercent inp)
          yearsToRet = round (retirementAge inp - currentAge inp)
          schedule   = projectCorpus yearsToRet
                         (ratePercent (preRetirementReturnPercent inp))
                         (ratePercent (annualStepUpPercent inp))
                         (currentCorpus inp) (monthlyInvestment inp)
          rt = Retirement
            { rtYearsToRet       = yearsToRet
            , rtYearsInRet       = round (lifeExpectancy inp - retirementAge inp)
            , rtRetirementAge    = retirementAge inp
            , rtInflation        = inflation
            , rtReturn           = ratePercent (postRetirementReturnPercent inp)
            , rtSwr              = ratePercent (safeWithdrawalRatePercent inp)
            , rtLivingAtRet      = compoundFor inflation yearsToRet
                                     (currentMonthlyExpense inp * 12)
                                   * (1 + expenseAdjustmentPercent inp / 100)
            , rtOtherIncomeToday = otherMonthlyIncome inp * 12
            , rtHealthcareToday  = healthcareAnnualToday inp
            , rtMedicalNearTerm  = ratePercent (medicalInflationPercent inp)
            , rtAgeing           = ratePercent (healthcareAgeingPercent inp)
            , rtTax              = Slabs (equitySharePercent inp / 100)
            }
      in simulate True rt (basisRatioOf (currentCorpus inp) schedule) start

    -- Withdrawal plus other income, less the year's tax, must equal spending
    -- — unless income alone covers spending and its own tax, in which case
    -- nothing is withdrawn.  The cases include income below spending, above
    -- it, and above it by less than its own tax bill.
    grossUpRoundTrips =
      and [ if w > 0
              then closeTo 1 (w + other - taxWith w) spending
              else other - taxWith 0 >= spending - 1
          | spending <- [300000, 720000, 1500000, 4000000, 9000000]
          , other    <- [0, 600000, 1520000, 2400000]
          , (e, g)   <- [(0.6, 0.5), (1, 0.85), (0, 0.3)]
          , let w = grossUpForSlabTax e g other spending
                taxWith x = taxOnYear (TaxableYear (other + (1 - e) * x * g) (e * x * g))
          ]

    -- The case that exposed the original bug: a Rs.24 lakh pension against
    -- Rs.7.2 lakh of spending pays its own Rs.3.1 lakh of tax with plenty to
    -- spare, so no corpus is needed at all.
    surplusIncomePaysItsOwnTax =
      checkSummaryOf defaultInput { otherMonthlyIncome = 200000
                                  , healthcareAnnualToday = 0 }
                     (\s -> closeTo 1e-6 (requiredCorpus s) 0)

    -- Income just above spending but short of its own tax bill: the corpus
    -- funds only the part of the tax the surplus cannot cover — more than
    -- nothing, less than the whole bill.  Rs.15.2 lakh against Rs.15 lakh of
    -- spending owes Rs.1.12 lakh of tax and has Rs.20,000 spare.
    partialSurplusFundsOnlyTheRest =
      let incomeToday = 1520000
          spendToday  = 1500000
          w = grossUpForSlabTax 0.6 0.8 incomeToday spendToday
          fullBill = taxOnYear (TaxableYear incomeToday 0)
      in w > 0 && w < fullBill

    requirementIsMonotonic =
      let req inp = either (const 0) (requiredCorpus . summary) (calculate inp)
          health  = [ req defaultInput { healthcareAnnualToday = h }
                    | h <- [0, 50000, 150000, 400000] ]
          flat    = [ req defaultInput { taxMode = FlatRate, flatTaxRatePercent = t }
                    | t <- [0, 5, 10, 20] ]
          rising xs = and (zipWith (<=) xs (drop 1 xs))
      in rising health && rising flat

    prescribedSipHitsTarget =
      case calculate defaultInput of
        Left _  -> False
        Right r ->
          let s     = summary r
              inp   = echoedInput r
              tuned = inp { monthlyInvestment = requiredMonthlyInvestment s }
          in case calculate tuned of
               Left _   -> False
               -- Compared with the tuned plan's own target: a bigger SIP
               -- changes how much of the corpus is gain, so it moves the tax
               -- and the target with it.  The SIP is solved to hit that.
               Right r' -> closeRel 1e-4 (projectedCorpus (summary r'))
                                         (requiredCorpus (summary r'))

    changeHitsTarget sip =
      let inp = defaultInput { monthlyInvestment = sip }
      in case calculate inp of
           Left _  -> False
           Right r ->
             let s     = summary r
                 tuned = inp { monthlyInvestment = sip + monthlyInvestmentChange s }
             in case calculate tuned of
                  Left _   -> False
                  Right r' -> closeRel 1e-4 (projectedCorpus (summary r'))
                                            (requiredCorpus (summary r'))
                              && closeTo 1e-9 (fundedGapPercent s)
                                              ((fundedRatio s - 1) * 100)

    underSavedPlanFails =
      let broke = defaultInput { currentCorpus = 0, monthlyInvestment = 2000 }
      in case calculate broke of
           Left _  -> False
           Right r -> let s = summary r
                      in verdict s == Lagging
                         && not (isNothing (corpusLastsUntilAge s))

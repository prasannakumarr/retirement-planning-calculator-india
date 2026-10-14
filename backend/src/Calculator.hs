{-# LANGUAGE OverloadedStrings #-}

module Calculator
  ( calculate
  , selfChecks
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

epsilon :: Double
epsilon = 1e-9

compoundFor :: Rate -> Int -> Double -> Double
compoundFor r years p = p * growthFactor r ^^ years

-- Fisher equation; nominal - inflation would overstate the real rate.
realRate :: Rate -> Rate -> Rate
realRate nominal inflation =
  Rate (growthFactor nominal / growthFactor inflation - 1)

-- Twelfth root, not /12: returns are quoted as effective annual CAGR.
monthlyRate :: Rate -> Rate
monthlyRate r = Rate (growthFactor r ** (1 / 12) - 1)

-- SIPs are paid at the start of each month (annuity-due).
fvOfOneYearOfSips :: Rate -> Rupees -> Rupees
fvOfOneYearOfSips annual monthly
  | abs rm < epsilon = monthly * 12
  | otherwise        = monthly * annuityDueFactor
  where
    Rate rm          = monthlyRate annual
    annuityDueFactor = ((1 + rm) ^^ (12 :: Int) - 1) / rm * (1 + rm)

pvOfInflatingWithdrawals
  :: Rate
  -> Rate
  -> Int
  -> Rupees
  -> Rupees
pvOfInflatingWithdrawals nominal inflation n firstWithdrawal
  | n <= 0            = 0
  | abs rr < epsilon  = firstWithdrawal * fromIntegral n
  | otherwise         = firstWithdrawal * levelFactor * (1 + rr)
  where
    Rate rr     = realRate nominal inflation
    levelFactor = (1 - (1 + rr) ** negate (fromIntegral n)) / rr

corpusForWithdrawalRate
  :: Rate
  -> Rupees
  -> Rupees
corpusForWithdrawalRate (Rate swr) need
  | swr < epsilon = 0
  | otherwise     = need / swr

projectCorpus
  :: Int
  -> Rate
  -> Rate
  -> Rupees
  -> Rupees
  -> [(Rupees, Rupees, Rupees, Rupees)]
projectCorpus years r stepUp opening firstYearMonthly = go 1 opening
  where
    go year balance
      | year > years = []
      | otherwise    = (balance, contribution, growth, closing) : go (year + 1) closing
      where
        monthly       = firstYearMonthly * growthFactor stepUp ^^ (year - 1)
        contribution  = monthly * 12

        balanceGrowth = balance * unRate r
        sipGrowth     = fvOfOneYearOfSips r monthly - contribution

        growth        = balanceGrowth + sipGrowth
        closing       = balance + contribution + growth

fvPerRupeeOfSip :: Int -> Rate -> Rate -> Double
fvPerRupeeOfSip years r stepUp =
  case projectCorpus years r stepUp 0 1 of
    [] -> 0
    xs -> let (_, _, _, closing) = last xs in closing

requiredMonthlyFor
  :: Int
  -> Rate
  -> Rate
  -> Rupees
  -> Rupees
  -> Rupees
requiredMonthlyFor years r stepUp fvExisting required
  | perRupee < epsilon = 0
  | otherwise          = max 0 ((required - fvExisting) / perRupee)
  where
    perRupee = fvPerRupeeOfSip years r stepUp

medicalTaperYears :: Int
medicalTaperYears = 20

medicalLongRunPremium :: Double
medicalLongRunPremium = 0.02

medicalRateInYear :: Rate -> Rate -> Int -> Rate
medicalRateInYear (Rate nearTerm) (Rate general) s =
  Rate (nearTerm + (longRun - nearTerm) * progress)
  where
    longRun  = min nearTerm (general + medicalLongRunPremium)
    progress = fromIntegral (min s medicalTaperYears)
             / fromIntegral medicalTaperYears

medicalPriceFactor :: Rate -> Rate -> Int -> Double
medicalPriceFactor nearTerm general t =
  product [ growthFactor (medicalRateInYear nearTerm general s) | s <- [0 .. t - 1] ]

ageingFactor :: Rate -> Double -> Double -> Double
ageingFactor ageing baseAge age =
  growthFactor ageing ** (band age - band baseAge)
  where
    band x = min 85 (max 60 x)

data TaxTreatment
  = Untaxed
  | Flat Double
  | Slabs Double

data Retirement = Retirement
  { rtYearsToRet       :: Int
  , rtYearsInRet       :: Int
  , rtRetirementAge    :: Double
  , rtInflation        :: Rate
  , rtReturn           :: Rate
  , rtSwr              :: Rate
  , rtLivingAtRet      :: Rupees
  , rtOtherIncomeToday :: Rupees
  , rtHealthcareToday  :: Rupees
  , rtMedicalNearTerm  :: Rate
  , rtAgeing           :: Rate
  , rtTax              :: TaxTreatment
  }

data YearNeed = YearNeed
  { ynYear             :: Int
  , ynAge              :: Double
  , ynDeflator         :: Double
  , ynLiving           :: Rupees
  , ynHealthcare       :: Rupees
  , ynOtherIncome      :: Rupees
  , ynLivingFromCorpus :: Rupees
  , ynHealthFromCorpus :: Rupees
  }

ynNeed :: YearNeed -> Rupees
ynNeed y = ynLivingFromCorpus y + ynHealthFromCorpus y

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

data SimYear = SimYear
  { syNeed         :: YearNeed
  , syOpening      :: Rupees
  , syGainFraction :: Double
  , syGross        :: Rupees
  , syWithdrawal   :: Rupees
  , syGrowth       :: Rupees
  , syClosing      :: Rupees
  }

-- Uncapped runs may go negative so the depletion solver sees a smooth function.
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

requiredCorpusFor :: Retirement -> Double -> Rupees
requiredCorpusFor rt basisRatio = uncurry max (requiredCorpora rt basisRatio)

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
  , drwClosingReal     = syClosing sy
                           / growthFactor inflation ^^ (yearsToRet + ynYear y)
  }
  where
    y   = syNeed sy
    d   = ynDeflator y
    tax = max 0 (syGross sy - ynNeed y)

shareOf :: Double -> Double -> Double
shareOf part whole = if whole > epsilon then part / whole * 100 else 0

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

verdictFor :: Double -> Verdict
verdictFor ratio
  | ratio >= 1.10 = Comfortable
  | ratio >= 0.95 = OnTrack
  | ratio >= 0.75 = SlightlyBehind
  | otherwise     = Lagging

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

calculate :: PlanInput -> Either CalcError PlanResult
calculate input = do
  validate input

  let inflation = ratePercent (inflationPercent i)
      preReturn = ratePercent (preRetirementReturnPercent i)
      postReturn = ratePercent (postRetirementReturnPercent i)
      stepUp    = ratePercent (annualStepUpPercent i)
      swr       = ratePercent (safeWithdrawalRatePercent i)

      yearsToRet = round (retirementAge i - currentAge i) :: Int
      yearsInRet = round (lifeExpectancy i - retirementAge i) :: Int

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

      fvExisting = compoundFor preReturn yearsToRet (currentCorpus i)
      schedule   = projectCorpus yearsToRet preReturn stepUp (currentCorpus i)
                                 (monthlyInvestment i)
      projected  = case schedule of
                     [] -> currentCorpus i
                     xs -> let (_, _, _, c) = last xs in c
      fvInvestments = projected - fvExisting

      basisRatio = basisRatioOf (currentCorpus i) schedule

      (depletionCorpus, swrCorpus) = requiredCorpora retirement basisRatio
      required        = max depletionCorpus swrCorpus
      methodUsed      = if swrCorpus >= depletionCorpus
                          then "safe withdrawal rate" :: T.Text
                          else "corpus depletion"

      livingOnly     = requiredCorpusFor retirement { rtHealthcareToday = 0
                                                    , rtTax = Untaxed } basisRatio
      beforeTax      = requiredCorpusFor retirement { rtTax = Untaxed } basisRatio

      gap      = projected - required
      ratio    = if required > epsilon then projected / required else 1
      v        = verdictFor ratio

      sipFor target = requiredMonthlyFor yearsToRet preReturn stepUp fvExisting target
      targetWithSip m = requiredCorpusFor retirement
                          (basisRatioOf (currentCorpus i)
                             (projectCorpus yearsToRet preReturn stepUp (currentCorpus i) m))
      settle n m
        | n >= (30 :: Int) || abs (m' - m) < 0.01 = m'
        | otherwise                               = settle (n + 1) m'
        where m' = sipFor (targetWithSip m)
      -- Fixed point: a bigger SIP changes the gain share, hence the tax and target.
      requiredMonthly = settle 0 (sipFor required)
      extraMonthly    = max 0 (requiredMonthly - monthlyInvestment i)

      targetSchedule = projectCorpus yearsToRet preReturn stepUp (currentCorpus i)
                                     requiredMonthly
      accRows = buildAccumulationRows (currentAge i) (currentCorpus i)
                                      schedule targetSchedule

      simYears = simulate True retirement basisRatio projected
      drawRows = map (toDrawdownRow yearsToRet inflation) simYears

      ranOutIn   = find (\sy -> syWithdrawal sy < syGross sy - 1) simYears
      lastsUntil = fmap (ynAge . syNeed) ranOutIn

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

      toTodaysRupees x = x / growthFactor inflation ^^ yearsToRet

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

basisRatioOf :: Rupees -> [(Rupees, Rupees, Rupees, Rupees)] -> Double
basisRatioOf corpusToday schedule
  | finalCorpus > epsilon = min 1 (costBasis / finalCorpus)
  | otherwise             = 1
  where
    costBasis   = corpusToday + sum [ c | (_, c, _, _) <- schedule ]
    finalCorpus = case schedule of
                    [] -> corpusToday
                    xs -> let (_, _, _, c) = last xs in c

buildAccumulationRows
  :: Double
  -> Rupees
  -> [(Rupees, Rupees, Rupees, Rupees)]
  -> [(Rupees, Rupees, Rupees, Rupees)]
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

  , ( "matches the independently computed reference case to within 0.5%"
    , matchesReferenceCase )

  , ( "no healthcare and no tax reproduces the closed-form annuity exactly"
    , reproducesClosedForm )

  , ( "spending the DEPLETION corpus leaves it exhausted at life expectancy"
    , requiredCorpusEndsAtZero )

  , ( "investing the REQUIRED monthly amount hits the required corpus exactly"
    , prescribedSipHitsTarget )

  , ( "a plainly under-saved plan is reported as lagging, and runs out early"
    , underSavedPlanFails )

  , ( "today's SIP plus the stated monthly change hits the target, both ways"
    , and [ changeHitsTarget sip | sip <- [10000, 30000, 100000] ] )

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

    closeRel tol actual expected =
      abs (actual - expected) <= tol * max 1 (abs expected)

    legacyInput = defaultInput { healthcareAnnualToday = 0, taxMode = NoTax }

    checkSummaryOf inp p = either (const False) (p . summary) (calculate inp)
    checkSummary = checkSummaryOf defaultInput

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
           closeRel 5e-3 (requiredCorpusDepletion s) 69469000
           && closeRel 5e-3 (fvOfCurrentCorpus s)    29960000)

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
               all (\sy -> syWithdrawal sy >= syGross sy - 1) (init rows)
               && syClosing end <= 0.01 * syWithdrawal end)

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

    surplusIncomePaysItsOwnTax =
      checkSummaryOf defaultInput { otherMonthlyIncome = 200000
                                  , healthcareAnnualToday = 0 }
                     (\s -> closeTo 1e-6 (requiredCorpus s) 0)

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

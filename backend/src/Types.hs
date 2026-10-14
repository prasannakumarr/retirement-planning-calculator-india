{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module Types
  ( Rupees
  , Rate(..)
  , ratePercent
  , growthFactor
  , PlanInput(..)
  , TaxMode(..)
  , defaultInput
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

type Rupees = Double

-- A decimal fraction: Rate 0.06 is 6% p.a.
newtype Rate = Rate { unRate :: Double }
  deriving (Show, Eq)

ratePercent :: Double -> Rate
ratePercent p = Rate (p / 100)

growthFactor :: Rate -> Double
growthFactor (Rate r) = 1 + r

-- Percentages arrive as plain numbers (6.5 = 6.5%); money in today's rupees.
data PlanInput = PlanInput
  { currentAge              :: Double
  , retirementAge           :: Double
  , lifeExpectancy          :: Double
  , currentMonthlyExpense   :: Rupees
  , currentCorpus           :: Rupees
  , monthlyInvestment       :: Rupees
  , annualStepUpPercent     :: Double
  , inflationPercent        :: Double
  , preRetirementReturnPercent  :: Double
  , postRetirementReturnPercent :: Double
  , expenseAdjustmentPercent :: Double
  , otherMonthlyIncome      :: Rupees
  , safeWithdrawalRatePercent :: Double
  , healthcareAnnualToday   :: Rupees
  , medicalInflationPercent :: Double
  , healthcareAgeingPercent :: Double
  , taxMode                 :: TaxMode
  , flatTaxRatePercent      :: Double
  , equitySharePercent      :: Double
  } deriving (Show, Generic)

instance FromJSON PlanInput where
  parseJSON = genericParseJSON defaultOptions

instance ToJSON PlanInput where
  toJSON    = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

data TaxMode
  = EstimateFromSlabs
  | FlatRate
  | NoTax
  deriving (Show, Eq, Generic)

instance FromJSON TaxMode
instance ToJSON TaxMode

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
  , healthcareAnnualToday       = 150000
  , medicalInflationPercent     = 10
  , healthcareAgeingPercent     = 2.5
  , taxMode                     = EstimateFromSlabs
  , flatTaxRatePercent          = 10
  , equitySharePercent          = 60
  }

data Verdict
  = Comfortable
  | OnTrack
  | SlightlyBehind
  | Lagging
  deriving (Show, Eq, Generic)

instance ToJSON Verdict

data AccumulationRow = AccumulationRow
  { accYear          :: Int
  , accAge           :: Double
  , accOpeningCorpus :: Rupees
  , accContribution  :: Rupees
  , accGrowth        :: Rupees
  , accClosingCorpus :: Rupees
  , accTargetCorpus  :: Rupees
  } deriving (Show, Generic)

instance ToJSON AccumulationRow where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

data DrawdownRow = DrawdownRow
  { drwYear          :: Int
  , drwAge           :: Double
  , drwOpeningCorpus :: Rupees
  , drwWithdrawal    :: Rupees
  , drwLivingCost    :: Rupees
  , drwHealthcareCost :: Rupees
  , drwTax           :: Rupees
  , drwLivingReal    :: Rupees
  , drwHealthcareReal :: Rupees
  , drwTaxReal       :: Rupees
  , drwHealthcareShare :: Double
  , drwGainFraction  :: Double
  , drwGrowth        :: Rupees
  , drwClosingCorpus :: Rupees
  , drwClosingReal   :: Rupees
  } deriving (Show, Generic)

instance ToJSON DrawdownRow where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

data Summary = Summary
  { yearsToRetirement        :: Double
  , yearsInRetirement        :: Double
  , monthlyExpenseAtRetirement :: Rupees
  , annualExpenseAtRetirement  :: Rupees
  , annualNeedFromCorpus       :: Rupees
  , healthcareAtRetirement     :: Rupees
  , healthcareMonthlyAtRetirement :: Rupees
  , grossFirstYearWithdrawal   :: Rupees
  , firstYearTaxRate           :: Double
  , averageTaxRate             :: Double
  , healthcareShareAtRetirement :: Double
  , healthcareShareAt75        :: Maybe Double
  , healthcareShareAtEnd       :: Double
  , requiredForLiving          :: Rupees
  , requiredForHealthcare      :: Rupees
  , requiredForTax             :: Rupees
    -- The larger of the depletion and SWR methods.
  , requiredCorpus           :: Rupees
  , requiredCorpusDepletion  :: Rupees
  , requiredCorpusSwr        :: Rupees
  , requiredCorpusMethod     :: Text
  , projectedCorpus          :: Rupees
  , surplusOrGap             :: Rupees
  , fundedRatio              :: Double
  , verdict                  :: Verdict
  , verdictMessage           :: Text
  , requiredMonthlyInvestment   :: Rupees
  , additionalMonthlyInvestment :: Rupees
  , fundedGapPercent            :: Double
  , monthlyInvestmentChange     :: Rupees
  , monthlyInvestmentChangePercent :: Maybe Double
  , requiredCorpusInTodaysRupees  :: Rupees
  , projectedCorpusInTodaysRupees :: Rupees
  , corpusMultipleRequired   :: Double
  , corpusMultipleDepletion  :: Double
  , realReturnPreRetirement  :: Double
  , realReturnPostRetirement :: Double
  , impliedWithdrawalRate    :: Double
  , corpusLastsUntilAge      :: Maybe Double
  , fvOfCurrentCorpus        :: Rupees
  , fvOfFutureInvestments    :: Rupees
  } deriving (Show, Generic)

instance ToJSON Summary where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

data PlanResult = PlanResult
  { summary      :: Summary
  , accumulation :: [AccumulationRow]
  , drawdown     :: [DrawdownRow]
  , echoedInput  :: PlanInput
  } deriving (Show, Generic)

instance ToJSON PlanResult where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

newtype CalcError = CalcError { errorMessage :: Text }
  deriving (Show, Generic)

instance ToJSON CalcError where
  toJSON     = genericToJSON defaultOptions
  toEncoding = genericToEncoding defaultOptions

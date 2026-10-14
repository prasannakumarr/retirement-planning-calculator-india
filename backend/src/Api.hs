{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Api
-- Description : The HTTP skin over "Calculator".
--
-- This module is deliberately thin.  It knows about routes, JSON and status
-- codes; it knows nothing about retirement.  Every number the API returns is
-- produced by 'Calculator.calculate' and simply forwarded.
--
-- Keeping the split this sharp means the financial logic can be read, tested
-- and argued about without a web server anywhere in the picture — and it means
-- a bug in the maths can never be mistaken for a bug in the transport.
module Api
  ( app
  , corsPolicy
  ) where

import           Data.Aeson                 (eitherDecode)
import qualified Data.Text.Lazy             as TL
import           Network.HTTP.Types.Status  (badRequest400)
import           Network.Wai                (Middleware)
import           Network.Wai.Middleware.Cors (CorsResourcePolicy (..), cors,
                                              simpleCorsResourcePolicy)
import           Web.Scotty

import           Calculator                 (calculate)
import           Types

-- | Allow the Vite dev server to talk to us.
--
-- The frontend runs on port 5173 and this API on 8080, which makes every
-- request cross-origin as far as the browser is concerned.  Without this
-- middleware the browser blocks the response before any JavaScript sees it —
-- and the symptom is a silent network failure rather than an error, which
-- wastes a lot of debugging time the first time you meet it.
--
-- This policy is wide open, which is correct for something that runs on
-- localhost and fine because the API holds no data and has no notion of a
-- user.  A deployed version would pin 'corsOrigins' to a known host.
corsPolicy :: Middleware
corsPolicy = cors (const (Just policy))
  where
    policy = simpleCorsResourcePolicy
      { corsRequestHeaders = ["Content-Type"]
      , corsMethods        = ["GET", "POST", "OPTIONS"]
      }

-- | The complete set of routes.
app :: ScottyM ()
app = do
  middleware corsPolicy

  -- A liveness probe, so the frontend can tell "backend is down" apart from
  -- "backend rejected my numbers" and show the user the right message.
  get "/api/health" $
    json ("ok" :: String)

  -- The starting scenario.  Serving the defaults from the backend rather than
  -- hard-coding them in the Svelte form keeps a single source of truth: the
  -- assumptions live next to the maths that consumes them.
  get "/api/defaults" $
    json defaultInput

  -- The one route that matters.
  post "/api/calculate" $ do
    requestBody <- body
    case eitherDecode requestBody of
      -- Malformed JSON, or a field of the wrong type.  Aeson's message is
      -- passed through because it names the offending field, which is exactly
      -- what you want while wiring up a frontend.
      Left err -> do
        status badRequest400
        json (CalcError ("Could not read the request: " <> TL.toStrict (TL.pack err)))

      Right planInput ->
        -- Well-formed JSON, but the numbers may still be nonsense (retiring
        -- before you were born, and so on).  'calculate' validates before it
        -- computes, so a rejection here is a message written for the user.
        case calculate planInput of
          Left calcErr -> do
            status badRequest400
            json calcErr
          Right result ->
            json result

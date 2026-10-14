{-# LANGUAGE OverloadedStrings #-}

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

corsPolicy :: Middleware
corsPolicy = cors (const (Just policy))
  where
    policy = simpleCorsResourcePolicy
      { corsRequestHeaders = ["Content-Type"]
      , corsMethods        = ["GET", "POST", "OPTIONS"]
      }

app :: ScottyM ()
app = do
  middleware corsPolicy

  get "/api/health" $
    json ("ok" :: String)

  get "/api/defaults" $
    json defaultInput

  post "/api/calculate" $ do
    requestBody <- body
    case eitherDecode requestBody of
      Left err -> do
        status badRequest400
        json (CalcError ("Could not read the request: " <> TL.toStrict (TL.pack err)))

      Right planInput ->
        case calculate planInput of
          Left calcErr -> do
            status badRequest400
            json calcErr
          Right result ->
            json result

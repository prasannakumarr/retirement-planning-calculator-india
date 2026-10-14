{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Main
-- Description : Entry point — runs the self-checks, then serves the API.
--
-- Start with @cabal run@ from the @backend@ directory.  The server listens on
-- port 8080; the Svelte frontend runs separately on 5173 and calls across.
module Main (main) where

import           Control.Monad (forM_, unless)
import           System.Exit   (exitFailure)
import           System.IO     (BufferMode (LineBuffering), hSetBuffering,
                                stdout)
import           Network.Wai.Handler.Warp (defaultSettings, setHost, setPort)
import           Web.Scotty    (Options (settings), defaultOptions,
                                scottyOpts)

import           Api           (app)
import           Calculator    (selfChecks)

-- | The port the API listens on.  The frontend's dev proxy expects this.
port :: Int
port = 8080

-- | Listen on the loopback interface only.
--
-- Scotty's default binds every interface, which would expose this API (and its
-- wide-open CORS policy) to anyone on the same network.  It is only ever
-- meant to be reached by the Vite dev server on the same machine.
serverOptions :: Options
serverOptions = defaultOptions
  { settings = setHost "127.0.0.1" (setPort port defaultSettings) }

-- | Run the arithmetic self-checks and __refuse to start__ if any fail.
--
-- This is the belt-and-braces part of the design.  A retirement calculator
-- that is wrong is worse than one that does not run: a server that refuses to
-- boot gets fixed in five minutes, whereas a server that quietly understates
-- a corpus by 20% might never be caught at all.  The checks cost a fraction of
-- a millisecond, so there is no reason not to pay for them on every start.
runSelfChecks :: IO ()
runSelfChecks = do
  putStrLn "Running arithmetic self-checks..."
  forM_ selfChecks $ \(name, passed) ->
    putStrLn $ "  " <> (if passed then "PASS  " else "FAIL  ") <> name

  let failures = length [() | (_, False) <- selfChecks]
  unless (failures == 0) $ do
    putStrLn ""
    putStrLn $ "ABORTING: " <> show failures <> " self-check(s) failed."
    putStrLn "The calculator's formulas disagree with each other, so every"
    putStrLn "answer it produces would be suspect. Refusing to serve."
    exitFailure

  putStrLn $ "All " <> show (length selfChecks) <> " checks passed.\n"

main :: IO ()
main = do
  -- Without this, output is block-buffered when stdout is piped and the
  -- startup banner never appears until the process exits.
  hSetBuffering stdout LineBuffering

  runSelfChecks

  putStrLn $ "Retirement calculator API listening on http://127.0.0.1:" <> show port
  putStrLn "  GET  /api/health"
  putStrLn "  GET  /api/defaults"
  putStrLn "  POST /api/calculate"
  scottyOpts serverOptions app

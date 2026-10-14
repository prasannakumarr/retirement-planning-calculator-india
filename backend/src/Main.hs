{-# LANGUAGE OverloadedStrings #-}

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

port :: Int
port = 8080

-- Loopback only: Scotty's default binds every interface.
serverOptions :: Options
serverOptions = defaultOptions
  { settings = setHost "127.0.0.1" (setPort port defaultSettings) }

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
  hSetBuffering stdout LineBuffering

  runSelfChecks

  putStrLn $ "Retirement calculator API listening on http://127.0.0.1:" <> show port
  putStrLn "  GET  /api/health"
  putStrLn "  GET  /api/defaults"
  putStrLn "  POST /api/calculate"
  scottyOpts serverOptions app

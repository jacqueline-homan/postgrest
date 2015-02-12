module Main where

import Paths_postgrest (version)

import App
import Middleware
import Error(errResponse)

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Data.String.Conversions (cs)
import Network.Wai (strictRequestBody)
import Network.Wai.Middleware.Cors (cors)
import Network.Wai.Handler.Warp hiding (Connection)
import Network.Wai.Middleware.Gzip (gzip, def)
import Network.Wai.Middleware.Static (staticPolicy, only)
import Data.List (intercalate)
import Data.Version (versionBranch)
import qualified Hasql as H
import qualified Hasql.Postgres as P
import Data.Monoid
import System.Exit(exitFailure, exitSuccess)

import Config (AppConfig(..), usage, corsPolicy, argParser)
import System.Environment(getArgs)
import System.Console.GetOpt(OptDescr(..), ArgDescr(..), ArgOrder(Permute),
  getOpt)

main :: IO ()
main = do
  args <- getArgs
  case getOpt Permute [Option "?h" ["help"] (NoArg ()) "show this help"] args of
    ([()], _, _) -> help []
    _ -> case argParser args of
           Left errs -> help errs
           Right conf -> runApp conf

help :: [String] -> IO ()
help [] = putStr usage >> exitSuccess
help errs = do
  putStr $ "missing required argument(s): " ++ (intercalate ", " errs) ++
    '\n':usage
  exitFailure

runApp::AppConfig->IO()
runApp conf = do
  let port = configPort conf

  unless (configSecure conf) $
    putStrLn "WARNING, running in insecure mode, auth will be in plaintext"
  Prelude.putStrLn $ "Listening on port " ++
    (show $ configPort conf :: String)

  let pgSettings = P.ParamSettings (cs $ configDbHost conf)
                     (fromIntegral $ configDbPort conf)
                     (cs $ configDbUser conf)
                     (cs $ configDbPass conf)
                     (cs $ configDbName conf)
      appSettings = setPort port
                  . setServerName (cs $ "postgrest/" <> prettyVersion)
                  $ defaultSettings
      middle =
        (if configSecure conf then redirectInsecure else id)
        . gzip def . cors corsPolicy
        . staticPolicy (only [("favicon.ico", "static/favicon.ico")])
      anonRole = cs $ configAnonRole conf
      currRole = cs $ configDbUser conf

  poolSettings <- maybe (fail "Improper session settings") return $
                H.poolSettings (fromIntegral $ configPool conf) 30
  pool :: H.Pool P.Postgres
          <- H.acquirePool pgSettings poolSettings

  runSettings appSettings $ middle $ \req respond -> do
    body <- strictRequestBody req
    resOrError <- liftIO $ H.session pool $ H.tx Nothing $
      authenticated currRole anonRole (app body) req
    either (respond . errResponse) respond resOrError

  where
    prettyVersion = intercalate "." $ map show $ versionBranch version

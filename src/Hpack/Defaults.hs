{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE LambdaCase #-}
module Hpack.Defaults (
  ensure
, Defaults(..)
#ifdef TEST
, Result(..)
, ensureFile
#endif
) where

import           Network.HTTP.Types
import           Network.HTTP.Client
import           Network.HTTP.Client.TLS
import           Data.List
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Char8 as B
import           System.FilePath
import           System.Directory

import           Hpack.Syntax.Defaults

type URL = String

defaultsUrl :: DefaultsGithub -> URL
defaultsUrl DefaultsGithub{..} = "https://raw.githubusercontent.com/" ++ defaultsGithubOwner ++ "/" ++ defaultsGithubRepo ++ "/" ++ defaultsGithubRef ++ "/" ++ intercalate "/" defaultsGithubPath

defaultsCachePath :: FilePath -> DefaultsGithub -> FilePath
defaultsCachePath dir DefaultsGithub{..} = joinPath $
  dir : "defaults" : defaultsGithubOwner : defaultsGithubRepo : defaultsGithubRef : defaultsGithubPath

data Result = Found | NotFound | Failed String
  deriving (Eq, Show)

get :: URL -> FilePath -> IO Result
get url file = do
  manager <- newManager tlsManagerSettings
  request <- parseRequest url
  response <- httpLbs request manager
  case responseStatus response of
    Status 200 _ -> do
      createDirectoryIfMissing True (takeDirectory file)
      LB.writeFile file (responseBody response)
      return Found
    Status 404 _ -> return NotFound
    status -> return (Failed $ "Error while downloading " ++ url ++ " (" ++ formatStatus status ++ ")")

formatStatus :: Status -> String
formatStatus (Status code message) = show code ++ " " ++ B.unpack message

ensure :: FilePath -> Defaults -> IO (Either String FilePath)
ensure dir = \ case
  DefaultsGithub_ defaults -> do
    let
      url = defaultsUrl defaults
      file = defaultsCachePath dir defaults
    ensureFile file url >>= \ case
      Found -> return (Right file)
      NotFound -> return (Left $ notFound url)
      Failed err -> return (Left err)
  DefaultsLocal_ (DefaultsLocal file) ->
    doesFileExist file >>= \ case
      True -> return (Right file)
      False -> return (Left $ notFound file)
  where
    notFound file = "Invalid value for \"defaults\"! File " ++ file ++ " does not exist!"

ensureFile :: FilePath -> URL -> IO Result
ensureFile file url = do
  doesFileExist file >>= \ case
    True -> return Found
    False -> get url file

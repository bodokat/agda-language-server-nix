{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Server (run) where

-- entry point of the LSP server

-- import Language.LSP.Types (TextDocumentSyncOptions(..), SaveOptions(..))

import qualified Agda.Interaction.Base as Agda
import qualified Agda.Interaction.Response as Agda
import Common
import Control.Concurrent
import qualified Control.Concurrent.Foreman as Foreman
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader
import qualified Core
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as JSON
import Data.Text (Text, pack)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import GHC.Generics (Generic)
import GHC.IO.IOMode (IOMode (ReadWriteMode))
import Language.LSP.Server
import Language.LSP.Types hiding (TextDocumentSyncClientCapabilities (..))
import Lispify (responseAbbr)
import Network.Simple.TCP (HostPreference (Host), serve)
import Network.Socket (socketToHandle)

--------------------------------------------------------------------------------

run :: Bool -> IO Int
run devMode = do
  env <- createInitEnv devMode

  if devMode
    then do
      let port = "4000"
      --

      putStrLn $ "== opening a dev server at port " ++ port ++ " =="
      serve (Host "localhost") port $ \(sock, _remoteAddr) -> do
        putStrLn "== connection established =="
        handle <- socketToHandle sock ReadWriteMode
        _ <- runServerWithHandles handle handle (serverDefn env)
        putStrLn "== connection closed =="
    else do
      runServer (serverDefn env)
  where
    -- keeps reading and printing from `envLogChan`
    keepPrintLog :: Env -> IO ()
    keepPrintLog env = do
      result <- readChan (envLogChan env)
      when (envDevMode env) $ do
        Text.putStrLn result
      keepPrintLog env

    keepSendindReaction :: Env -> LanguageContextEnv () -> IO ()
    keepSendindReaction env ctxEnv = do
      response <- readChan (envReactionChan env)
      runLspT ctxEnv $ do
        callback <- liftIO $ Foreman.dispatch (envReactionController env)

        let value = JSON.toJSON response
        sendRequest (SCustomMethod "agda") value $ \result -> liftIO $ do
          writeChan (envLogChan env) $ "[Reaction] >>>> " <> pack (show value)
          callback ()
        liftIO $ writeChan (envLogChan env) $ "[Reaction] <<<< " <> pack (show value)

      keepSendindReaction env ctxEnv

    serverDefn :: Env -> ServerDefinition ()
    serverDefn env =
      ServerDefinition
        { onConfigurationChange = const $ pure $ Right (),
          doInitialize = \ctxEnv _req -> do
            putStrLn "[LSP] doInitialize"
            forkIO $ keepPrintLog env
            forkIO $ runReaderT Core.interact env
            forkIO $ keepSendindReaction env ctxEnv
            pure $ Right ctxEnv,
          staticHandlers = handlers,
          interpretHandler = \ctxEnv -> Iso (runServerLSP env ctxEnv) liftIO,
          options = lspOptions
        }
    lspOptions :: Options
    lspOptions =
      defaultOptions
        { textDocumentSync = Just syncOptions
        }

    -- these `TextDocumentSyncOptions` are essential for receiving notifications from the client
    syncOptions :: TextDocumentSyncOptions
    syncOptions =
      TextDocumentSyncOptions
        { _openClose = Just True, -- receive open and close notifications from the client
          _change = Nothing, -- receive change notifications from the client
          _willSave = Just False, -- receive willSave notifications from the client
          _willSaveWaitUntil = Just False, -- receive willSave notifications from the client
          _save = Just $ InR saveOptions
        }

    -- includes the document content on save, so that we don't have to read it from the disk
    saveOptions :: SaveOptions
    saveOptions = SaveOptions (Just True)

-- handlers of the LSP server
handlers :: Handlers (LspT () ServerM)
handlers =
  mconcat
    [ -- custom methods, not part of LSP
      requestHandler (SCustomMethod "agda") $ \req responder -> do
        let RequestMessage _ i _ params = req
        -- JSON Value => Request => Response
        response <- case JSON.fromJSON params of
          JSON.Error msg -> return $ ResCannotDecodeRequest $ show msg ++ "\n" ++ show params
          JSON.Success request -> handleRequest request
        -- respond with the Response
        responder $ Right $ JSON.toJSON response
    ]

--------------------------------------------------------------------------------

handleRequest :: Request -> LspT () ServerM Response
handleRequest request = do
  -- -- convert Request to LSP side effects
  -- toLSPSideEffects i request
  -- convert Request to Response
  toResponse request
  where
    toResponse :: Request -> LspT () ServerM Response
    toResponse ReqInitialize = return $ ResInitialize Core.getAgdaVersion
    toResponse (ReqCommand cmd) = do
      case Core.parseIOTCM cmd of
        Left error -> do
          lift $ writeLog $ "Error: parseIOTCM" <> pack error
          return ResCommandDone
        Right iotcm -> do
          lift $ do
            writeLog $ "[Request] " <> pack (show cmd)
            provideCommand iotcm
            return ResCommandDone

--------------------------------------------------------------------------------

data Request = ReqInitialize | ReqCommand String
  deriving (Generic)

instance FromJSON Request

--------------------------------------------------------------------------------

-- | Response
data Response
  = ResInitialize String
  | ResCommandDone
  | ResCannotDecodeRequest String
  deriving (Generic)

instance ToJSON Response

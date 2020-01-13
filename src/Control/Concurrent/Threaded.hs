{-# LANGUAGE
    DataKinds
  , RankNTypes
  , FlexibleContexts
  , ScopedTypeVariables
  #-}

module Control.Concurrent.Threaded where

import Control.Concurrent.Async (Async, async)
import Control.Concurrent.Chan.Scope (Scope (Read, Write))
import Control.Concurrent.Chan.Extra (ChanScoped (readOnly, allowReading))
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan.Typed (TChanRW, newTChanRW, readTChanRW)
import Control.Concurrent.STM.TMapMVar (TMapMVar, newTMapMVar, tryObserve)
import Control.Monad (forever)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Control.Aligned (MonadBaseControl (liftBaseWith))
import Data.Singleton.Class (Extractable (runSingleton))


-- | Segregates concurrently operating threads by some key type @k@. Returns the
-- thread that processes all other threads (this function is non-blocking), and the
-- channel that dispenses the outputs from each thread.
threaded :: forall m stM k input output
          . Ord k
         => MonadIO m
         => MonadBaseControl IO m stM
         => Extractable stM
         => -- | Incoming messages, identified by thread @k@
            TChanRW 'Write (k, input)
         -> -- | Process to spark in a new thread. When @m ()@ returns, the thread is considered \"dead\",
            -- and is internally cleaned up.
            (TChanRW 'Read input -> TChanRW 'Write output -> m ())
         -> m (Async (), TChanRW 'Read (k, output))
threaded incoming process = do
  ( threads :: TMapMVar k (Async (), TChanRW 'Read incoming, TChanRW 'Write outgoing)
    ) <- liftIO (atomically newTMapMVar)
  outgoing <- liftIO (atomically (readOnly <$> newTChanRW))

  threadRunner <- liftBaseWith $ \runInBase -> fmap (fmap runSingleton) $ async $ runInBase $ forever $ do
    (k, input) <- liftIO $ atomically $ readTChanRW $ allowReading incoming
    mThread <- liftIO $ atomically $ tryObserve threads k
    case mThread of
      Nothing -> undefined
      Just (thread, threadInput, threadOutput) -> undefined

  pure (threadRunner, outgoing)

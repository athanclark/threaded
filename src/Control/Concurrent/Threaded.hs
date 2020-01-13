{-# LANGUAGE
    DataKinds
  , RankNTypes
  , NamedFieldPuns
  , FlexibleContexts
  , ScopedTypeVariables
  #-}

module Control.Concurrent.Threaded where

import Control.Concurrent.Async (Async, async, cancel)
import Control.Concurrent.Chan.Scope (Scope (Read, Write))
import Control.Concurrent.Chan.Extra (ChanScoped (readOnly, allowReading, writeOnly, allowWriting))
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan.Typed (TChanRW, newTChanRW, readTChanRW, writeTChanRW)
import Control.Concurrent.STM.TMapMVar (TMapMVar, newTMapMVar, tryObserve, insertForce, tryLookup)
import Control.Monad (forever)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Trans.Control.Aligned (MonadBaseControl (liftBaseWith))
import Data.Singleton.Class (Extractable (runSingleton))



data ThreadedInternal incoming outgoing = ThreadedInternal
  { thread :: Async ()
  , outputRelay :: Async ()
  , threadInput :: TChanRW 'Read incoming
  , threadOutput :: TChanRW 'Write outgoing
  }


-- | Segregates concurrently operating threads by some key type @k@. Returns the
-- thread that processes all other threads (this function is non-blocking), and the
-- channel that dispenses the outputs from each thread.
threaded :: forall m stM k input output
          . Ord k
         => Show k
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
  ( threads :: TMapMVar k (ThreadedInternal incoming outgoing)
    ) <- liftIO (atomically newTMapMVar)
  outgoing <- liftIO (atomically (readOnly <$> newTChanRW))

  -- the main function that organizes the execution and plumbing of the threads
  threadRunner <- liftBaseWith $ \runInBase -> fmap (fmap runSingleton) $ async $ runInBase $ forever $ do
    (k, input) <- liftIO $ atomically $ readTChanRW $ allowReading incoming

    mThread <- liftIO $ atomically $ tryObserve threads k
    case mThread of
      Nothing -> do
        -- thread-specific channels
        threadInput' <- liftIO (atomically newTChanRW)
        let threadInput = readOnly threadInput'
        threadOutput' <- liftIO (atomically newTChanRW)
        let threadOutput = writeOnly threadOutput'

        -- initial input
        liftIO $ atomically $ writeTChanRW threadInput' input

        -- relays the process's output to the whole output
        outputRelay <- liftIO $ async $ forever $ atomically $ do
          output <- readTChanRW threadOutput'
          writeTChanRW (allowWriting outgoing) (k, output)

        -- main thread
        thread <- liftBaseWith $ \runInBase' -> fmap (fmap runSingleton) $ async $ runInBase' $ do
          process threadInput threadOutput
          -- thread finished processing
          mThread' <- liftIO $ atomically $ tryLookup threads k
          case mThread' of
            Nothing -> error $ "Thread's facilities don't exist: " ++ show k
            Just ThreadedInternal{thread = thread'} -> liftIO $ do
              -- kill the thread's supervisors
              cancel outputRelay
              cancel thread'

        -- store threads and channels
        liftIO $ atomically $
          insertForce threads k ThreadedInternal{thread,outputRelay,threadInput,threadOutput}


      -- thread is still processing - relay input to its channel
      Just ThreadedInternal{threadInput} ->
        liftIO $ atomically $ writeTChanRW (allowWriting threadInput) input

  pure (threadRunner, outgoing)

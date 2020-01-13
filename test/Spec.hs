import Control.Concurrent.Threaded (threaded)
import Control.Concurrent.Async (async, cancel)
import Control.Concurrent.Chan.Extra (writeOnly)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan.Typed (newTChanRW, readTChanRW, writeTChanRW)
import Control.Monad (forever)
import Control.Concurrent (threadDelay)


main :: IO ()
main = do
  let mult inputs outputs = do
        x <- atomically (readTChanRW inputs)
        putStrLn $ "Got x: " ++ show x
        y <- atomically (readTChanRW inputs)
        putStrLn $ "Got y: " ++ show y
        let o :: Integer
            o = (x :: Integer) * (y :: Integer)
        atomically (writeTChanRW outputs o)
        putStrLn $ "Sent o: " ++ show o
  incoming <- writeOnly <$> atomically newTChanRW

  (mainThread, outgoing) <- threaded incoming mult

  echoingThread <- async $ forever $ do
    (k,o) <- atomically (readTChanRW outgoing)
    putStrLn $ show k ++ ": " ++ show o

  atomically $ writeTChanRW incoming (1,1)
  atomically $ writeTChanRW incoming (2,2)
  atomically $ writeTChanRW incoming (3,3)
  atomically $ writeTChanRW incoming (1,1)
  atomically $ writeTChanRW incoming (2,2)
  atomically $ writeTChanRW incoming (3,3)

  threadDelay 1000000

  cancel echoingThread
  cancel mainThread

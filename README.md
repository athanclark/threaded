# threaded

Aims to make managed, horizontal scaling easier - given some process that reads from a concurrent channel,
writes to a concurrent channel, and returns when it's finished, then it should be horizontally scalable
with respect to some thread identifier:

```haskell
main :: IO ()
main = do
  let mult inputs outputs = do
        -- get first input
        x <- atomically (readTChanRW inputs)
        -- get second input
        y <- atomically (readTChanRW inputs)
        let o :: Integer
            o = (x :: Integer) * (y :: Integer)

        -- write output
        atomically (writeTChanRW outputs o)
        -- return

  -- incoming messages for specific threads
  incoming <- writeOnly <$> atomically newTChanRW

  (mainThread, outgoing) <- threaded incoming mult

  echoingThread <- async $ forever $ do
    -- do something with each thread's output
    (k,o) <- atomically (readTChanRW outgoing)
    putStrLn $ show k ++ ": " ++ show o

  atomically $ writeTChanRW incoming ("one",1)
  atomically $ writeTChanRW incoming ("two",2)
  atomically $ writeTChanRW incoming ("three",3)
  atomically $ writeTChanRW incoming ("one",1)
  atomically $ writeTChanRW incoming ("two",2)
  atomically $ writeTChanRW incoming ("three",3)

  threadDelay 1000000

  cancel echoingThread
  cancel mainThread
```

If the thread's identifier doesn't exist when sending an input, then the `threaded` manager will spark a new
one. If it does exist, then it just plumbs it to its input channel. Once the process returns, the thread with
that identifier is killed and garbage collected.

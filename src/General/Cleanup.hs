
-- | Code for ensuring cleanup actions are run.
module General.Cleanup(
    Cleanup, newCleanup, withCleanup,
    register, release, allocate, unprotect
    ) where

import Control.Exception
import qualified Data.HashMap.Strict as Map
import Data.IORef
import Data.List.Extra
import Data.Maybe


data S = S
    {unique :: {-# UNPACK #-} !Int -- next index to be used to items
    ,items :: !(Map.HashMap Int (IO ()))
    }

newtype Cleanup = Cleanup (IORef S)

data ReleaseKey = ReleaseKey (IORef S) {-# UNPACK #-} !Int


-- | Run with some cleanup scope. Regardless of exceptions/threads, all 'register' actions
--   will be run by the time it exits.
--   The 'register' actions will be run in reverse order, i.e. the last to be added will be run first.
withCleanup :: (Cleanup -> IO a) -> IO a
withCleanup act = do
    (c, clean) <- newCleanup
    act c `finally` clean

newCleanup :: IO (Cleanup, IO ())
newCleanup = do
    ref <- newIORef $ S 0 Map.empty
    let clean = mask_ $ do
            items <- atomicModifyIORef' ref $ \s -> (s{items=Map.empty}, items s)
            mapM_ snd $ sortOn (negate . fst) $ Map.toList items
    return (Cleanup ref, clean)


register :: Cleanup -> IO () -> IO ReleaseKey
register (Cleanup ref) act = atomicModifyIORef' ref $ \s -> let i = unique s in
    (S (unique s + 1) (Map.insert i act $ items s), ReleaseKey ref i)

unprotect :: ReleaseKey -> IO ()
unprotect (ReleaseKey ref i) = atomicModifyIORef' ref $ \s -> (s{items = Map.delete i $ items s}, ())

release :: ReleaseKey -> IO ()
release (ReleaseKey ref i) = mask_ $ do
    undo <- atomicModifyIORef' ref $ \s -> (s{items = Map.delete i $ items s}, Map.lookup i $ items s)
    fromMaybe (return ()) undo

allocate :: Cleanup -> IO a -> (a -> IO ()) -> IO a
allocate cleanup acquire release =
    mask_ $ do
        v <- acquire
        register cleanup $ release v
        return v

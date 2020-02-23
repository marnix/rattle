{-# LANGUAGE ScopedTypeVariables #-}

module Benchmark where

import System.Environment
import System.Process
import System.IO.Extra
import Control.Monad
import System.Time.Extra
import Numeric.Extra
import Development.Shake hiding (readFile', withTempDir)
import qualified Data.ByteString as BS
import Development.Rattle

main :: IO ()
main = do
    clean:run:other <- getArgs
    cmds <- map words . lines <$> readFile' run

    let benchmark lbl act = when (null other || lbl `elem` other) $ do
            putStrLn lbl
            let count = 5
            times <- replicateM count $ do
                Stdout (_ :: String) <- cmd Shell clean
                fst <$> duration act
            putStrLn $ unwords (map showDuration times) ++ " = " ++ showDuration (sum times / intToDouble count)

    benchmark "System.Process" $
        forM_ cmds $ \(command:args) ->
            callProcess command args

    benchmark "shake.cmd" $
        forM_ cmds cmd_

    benchmark "shake.cmd fsatrace" $
        forM_ cmds $ \xs -> cmd_ $ "fsatrace" : "rwmdqt" : "fsatrace.out" : "--" : xs

    benchmark "shake.cmd traced" $
        forM_ cmds $ \xs -> do
            _ :: [FSATrace BS.ByteString] <- cmd xs
            return ()

    let opts dir = rattleOptions{rattleFiles=dir, rattleProcesses=1, rattleUI=Just RattleQuiet, rattleNamedDirs=[]}
    benchmark "rattle" $
        withTempDir $ \dir ->
            rattleRun (opts dir){rattleSpeculate=Nothing, rattleShare=False} $
                forM_ cmds cmd

    benchmark "rattle share" $
        withTempDir $ \dir ->
            rattleRun (opts dir) $
                forM_ cmds cmd

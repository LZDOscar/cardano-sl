{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Type class necessary for Transaction processing (Txp)
-- and some useful getters and setters.

module Pos.Txp.MemState.Class
       ( MonadTxpMem
       , askTxpMem
       , TxpHolderTag
       , getUtxoModifier
       , getLocalTxsNUndo
       , getMemPool
       , getLocalTxs
       , getLocalTxsMap
       , getTxpExtra
       , modifyTxpLocalData
       , setTxpLocalData
       , clearTxpMemPool
       ) where

import           Universum

import qualified Control.Concurrent.STM as STM
import           Data.Default           (Default (..))
import qualified Data.HashMap.Strict    as HM
import qualified Ether
import           System.IO.Unsafe       (unsafePerformIO)
import           System.Wlog            (WithLogger, logDebug)
import           Formatting             (sformat, (%), shown)

import           Pos.Txp.Core.Types     (TxAux, TxId, TxOutAux)
import           Pos.Txp.MemState.Types (GenericTxpLocalData (..),
                                         GenericTxpLocalDataPure)
import           Pos.Txp.Toil.Types     (MemPool (..), UtxoModifier)
import           Pos.Util.TimeWarp      (currentTime)

data TxpHolderTag

-- | Reduced equivalent of @MonadReader (GenericTxpLocalData mw) m@.
type MonadTxpMem ext m =
    ( Ether.MonadReader TxpHolderTag (GenericTxpLocalData ext) m
    , WithLogger m
    )

askTxpMem :: MonadTxpMem ext m => m (GenericTxpLocalData ext)
askTxpMem = Ether.ask @TxpHolderTag

getTxpLocalData
    :: (MonadIO m, MonadTxpMem e m)
    => (GenericTxpLocalData e -> STM.STM a) -> m a
getTxpLocalData getter = askTxpMem >>= \ld -> do
    beginTime <- currentTime
    res <- atomically (getter ld)
    endTime <- currentTime
    let duration = endTime - beginTime
    logDebug $ sformat ("getTxpLocalData took " % shown) duration
    return res

getUtxoModifier
    :: (MonadTxpMem e m, MonadIO m)
    => m UtxoModifier
getUtxoModifier = getTxpLocalData (STM.readTVar . txpUtxoModifier)

getLocalTxsMap
    :: (MonadIO m, MonadTxpMem e m)
    => m (HashMap TxId TxAux)
getLocalTxsMap = _mpLocalTxs <$> getMemPool

getLocalTxs
    :: (MonadIO m, MonadTxpMem e m)
    => m [(TxId, TxAux)]
getLocalTxs = HM.toList <$> getLocalTxsMap

getLocalTxsNUndo
    :: (MonadIO m, MonadTxpMem e m)
    => m ([(TxId, TxAux)], HashMap TxId (NonEmpty TxOutAux))
getLocalTxsNUndo =
    getTxpLocalData $ \TxpLocalData {..} ->
        (,) <$> (HM.toList . _mpLocalTxs <$> STM.readTVar txpMemPool) <*>
        STM.readTVar txpUndos

getMemPool :: (MonadIO m, MonadTxpMem e m) => m MemPool
getMemPool = getTxpLocalData (STM.readTVar . txpMemPool)

getTxpExtra :: (MonadIO m, MonadTxpMem e m) => m e
getTxpExtra = getTxpLocalData (STM.readTVar . txpExtra)

txpLocalDataLock :: MVar ()
txpLocalDataLock = unsafePerformIO $ newMVar ()
{-# NOINLINE txpLocalDataLock #-}

modifyTxpLocalData
    :: (MonadIO m, MonadTxpMem ext m)
    => (GenericTxpLocalDataPure ext -> (a, GenericTxpLocalDataPure ext)) -> m a
modifyTxpLocalData f =
    askTxpMem >>= \TxpLocalData{..} -> do
        _ <- takeMVar txpLocalDataLock
        beginTime <- currentTime
        (res, setGaugeIO) <- atomically $ do
            curUM  <- STM.readTVar txpUtxoModifier
            curMP  <- STM.readTVar txpMemPool
            curUndos <- STM.readTVar txpUndos
            curTip <- STM.readTVar txpTip
            curExtra <- STM.readTVar txpExtra
            let (res, (newUM, newMP, newUndos, newTip, newExtra))
                  = f (curUM, curMP, curUndos, curTip, curExtra)
            STM.writeTVar txpUtxoModifier newUM
            STM.writeTVar txpMemPool newMP
            STM.writeTVar txpUndos newUndos
            STM.writeTVar txpTip newTip
            STM.writeTVar txpExtra newExtra
            setGauge <- STM.readTVar txpSetGauge
            pure (res, setGauge $ _mpLocalTxsSize newMP)
        endTime <- currentTime
        putMVar txpLocalDataLock ()
        let duration = endTime - beginTime
        logDebug $ sformat ("modifyTxpLocalData took " % shown) duration
        liftIO setGaugeIO
        pure res

setTxpLocalData
    :: (MonadIO m, MonadTxpMem ext m)
    => GenericTxpLocalDataPure ext -> m ()
setTxpLocalData x = modifyTxpLocalData (const ((), x))

clearTxpMemPool :: (MonadIO m, MonadTxpMem ext m, Default ext) => m ()
clearTxpMemPool = modifyTxpLocalData clearF
  where
    clearF (_, _, _, tip, _) = ((), (mempty, def, mempty, tip, def))

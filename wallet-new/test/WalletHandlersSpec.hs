module WalletHandlersSpec (spec) where

import           Universum

import           Test.Hspec

import qualified Cardano.Wallet.API.V1.LegacyHandlers.Wallets as V1
import qualified Pos.Core as Core
import qualified Pos.Wallet.Web.ClientTypes.Types as V0

import           Test.Pos.Chain.Genesis.Dummy (dummyK)

newSyncProgress :: Word64 -> Word64 -> V0.SyncProgress
newSyncProgress localBlocks totalBlks =
    V0.SyncProgress {
          V0._spLocalCD   = Core.ChainDifficulty (Core.BlockCount localBlocks)
        , V0._spNetworkCD = Just (Core.ChainDifficulty (Core.BlockCount totalBlks))
        , V0._spPeers     = 0
    }

totalBlocks :: Word64
totalBlocks = 10000

spec :: Spec
spec = describe "Wallet Handlers specs" $ do
        describe "the 'isNodeSufficientlySynced' function " $ do
                it "should return True if we are within k blocks behind" $ do
                    let (Core.BlockCount k) = dummyK
                    let progress = newSyncProgress (totalBlocks - k) totalBlocks
                    V1.isNodeSufficientlySynced dummyK progress `shouldBe` True
                it "should return False if we are more than k blocks behind" $ do
                    let (Core.BlockCount k) = dummyK
                    let progress = newSyncProgress (totalBlocks - k - 1) totalBlocks
                    V1.isNodeSufficientlySynced dummyK progress `shouldBe` False
                it "should return False if we cannot fetch the blockchain height" $ do
                    let (Core.BlockCount k) = dummyK
                    let progress = newSyncProgress (totalBlocks - k - 1) totalBlocks
                    V1.isNodeSufficientlySynced dummyK (progress { V0._spNetworkCD = Nothing })
                        `shouldBe` False

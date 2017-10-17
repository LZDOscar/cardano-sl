{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
module Cardano.Wallet.API.V0 where

import Cardano.Wallet.API.Types

import Servant

-- | "Mount" the legacy API here.
type API
   = "version" :> Get '[JSON] APIVersion
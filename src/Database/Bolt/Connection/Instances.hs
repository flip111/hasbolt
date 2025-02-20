{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards #-}

module Database.Bolt.Connection.Instances where

import           Prelude

import           Database.Bolt.Connection.Type
import           Database.Bolt.Value.Helpers
import           Database.Bolt.Value.Type

import           Control.Monad.Except           (MonadError (..))
import           Data.Map.Strict                (Map, insert, fromList, empty, (!))
import           Data.Text                      (Text)
import           GHC.Stack                      (HasCallStack)

instance ToStructure Request where
  toStructure RequestInit{..}           = Structure sigInit $ if isHello then [M $ helloMap agent token]
                                                                         else [T agent, M $ tokenMap token]
  toStructure RequestRun{..}            = Structure sigRun [T statement, M parameters]
  toStructure RequestRunV3{..}          = Structure sigRun [T statement, M parameters, M extra]
  toStructure RequestReset              = Structure sigReset []
  toStructure RequestAckFailure         = Structure sigAFail []
  toStructure RequestPullAll            = Structure sigPAll []
  toStructure RequestDiscardAll         = Structure sigDAll []
  toStructure RequestGoodbye            = Structure sigGBye []
  toStructure RequestBegin{..}          = Structure sigBegin [M extra]
  toStructure RequestCommit             = Structure sigCommit []
  toStructure RequestRollback           = Structure sigRollback []

instance FromStructure Response where
  fromStructure Structure{..}
    | signature == sigSucc = ResponseSuccess <$> extractMap fields
    | signature == sigRecs = pure $ ResponseRecord (removeExtList fields)
    | signature == sigIgn  = pure ResponseIgnored
    | signature == sigFail = ResponseFailure <$> extractMap fields
    | otherwise            = throwError $ Not "Response"
    where removeExtList :: HasCallStack => [Value] -> [Value]
          removeExtList [L x] = x
          removeExtList _     = error "Record must contain only a singleton list"

-- Response check functions

isSuccess :: Response -> Bool
isSuccess (ResponseSuccess _) = True
isSuccess _                   = False

isFailure :: Response -> Bool
isFailure (ResponseFailure _) = True
isFailure _                   = False

isIgnored :: Response -> Bool
isIgnored ResponseIgnored = True
isIgnored _               = False

isRecord :: Response -> Bool
isRecord (ResponseRecord _) = True
isRecord _                  = False

-- Helper functions

createInit :: BoltCfg -> Request
createInit BoltCfg{..} = RequestInit userAgent
                                     AuthToken { scheme      = authType
                                               , principal   = user
                                               , credentials = password
                                               }
                                     (isNewVersion version)

createRun :: Text -> Request
createRun stmt = RequestRun stmt empty


helloMap :: Text -> AuthToken  -> Map Text Value
helloMap a = insert "user_agent" (T a) . tokenMap

tokenMap :: AuthToken -> Map Text Value
tokenMap at = fromList [ "scheme"     =: scheme at
                       , "principal"   =: principal at
                       , "credentials" =: credentials at
                       ]

extractMap :: MonadError UnpackError m => [Value] -> m (Map Text Value)
extractMap [M mp] = pure mp
extractMap _      = throwError NotDict

mkFailure :: Response -> ResponseError
mkFailure ResponseFailure{..} =
  let (T code) = failMap ! "code"
      (T msg)  = failMap ! "message"
  in  KnownResponseFailure code msg
mkFailure _ = UnknownResponseFailure

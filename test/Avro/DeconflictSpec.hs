{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Avro.DeconflictSpec where

import Control.Monad.IO.Class
import Data.Avro              as A
import Data.Avro.Deconflict
import Data.Avro.Deriving
import Data.Avro.Schema
import Data.Either
import Data.List.NonEmpty     (NonEmpty (..))

import qualified Avro.Deconflict.A.Reader         as AR
import qualified Avro.Deconflict.A.Writer         as AW
import qualified Avro.Deconflict.B.Reader         as BR
import qualified Avro.Deconflict.B.Writer         as BW
import qualified Avro.Deconflict.C.Reader         as CR
import qualified Avro.Deconflict.C.Writer         as CW
import qualified Avro.Deconflict.D.Reader         as DR
import qualified Avro.Deconflict.D.Writer         as DW
import qualified Data.Avro.Decode                 as A (decodeAvro)
import qualified Data.Avro.Decode.Lazy            as AL
import qualified Data.Avro.Decode.Lazy.Deconflict as AL
import qualified Data.Avro.Deconflict             as A
import qualified Data.Avro.Types                  as Ty

import Test.Hspec

{-# ANN module ("HLint: ignore Redundant do"        :: String) #-}

spec :: Spec
spec = describe "Avro.DeconflictSpec" $ do
  describe "Type A" $ do
    it "should deconflict simple message" $ do
      let payload = A.encode $ AW.Inner 3
      let Right decodedAvro = A.decodeAvro AW.schema'Inner payload
      let Right deconflicted = deconflict AW.schema'Inner AR.schema'Inner decodedAvro
      fromAvro deconflicted `shouldBe` Success (AR.Inner 3 Nothing)

    it "should deconflict nested message" $ do
      let payload = A.encode AW.sampleValue
      let Right decodedAvro = A.decodeAvro AW.schema'Outer payload
      let Right deconflicted = deconflict AW.schema'Outer AR.schema'Outer decodedAvro

      fromAvro deconflicted `shouldBe` Success AR.sampleValue

    it "should deconflict strict container" $ do
      w <- A.encodeContainer [[AW.sampleValue]]
      A.decodeContainer w `shouldBe` [[AR.sampleValue]]

    it "should deconflict lazy container" $ do
      w <- A.encodeContainer [[AW.sampleValue]]
      AL.decodeContainer w `shouldBe` [Right AR.sampleValue]

    it "should deconflict lazy value" $ do
      let payload = A.encode AW.sampleValue
      let decodedAvro = AL.decodeAvro AW.schema'Outer payload
      let deconflicted = AL.deconflict AW.schema'Outer AR.schema'Outer decodedAvro

      AL.fromLazyAvro deconflicted `shouldBe` Success AR.sampleValue

    it "should deconflict strict value" $ do
      let payload = A.encode AW.sampleValue
      let Right decodedAvro = A.decodeAvro AW.schema'Outer payload
      let Right deconflicted = A.deconflict AW.schema'Outer AR.schema'Outer decodedAvro

      A.fromAvro deconflicted `shouldBe` Success AR.sampleValue


  describe "Type B" $ do
    it "should deconflict complex type" $ do
      let payload = A.encode BW.sampleValue
      let decodedAvro = AL.decodeAvro BW.schema'Foo payload
      let res = AL.deconflict BW.schema'Foo BR.schema'Foo decodedAvro

      AL.fromLazyAvro res `shouldBe` Success BR.sampleValue

    it "should deconflict lazy container" $ do
      w <- liftIO $ A.encodeContainer [[ BW.sampleValue ]]
      AL.decodeContainer w `shouldBe` [ Right BR.sampleValue ]

    it "should deconflict lazy value" $ do
      let payload = A.encode BW.sampleValue
      let decodedAvro = AL.decodeAvro BW.schema'Foo payload
      let deconflicted = AL.deconflict BW.schema'Foo BR.schema'Foo decodedAvro

      AL.fromLazyAvro deconflicted `shouldBe` Success BR.sampleValue

    it "should deconflict strict container" $ do
      w <- A.encodeContainer [[BW.sampleValue]]
      A.decodeContainer w `shouldBe` [[BR.sampleValue]]

    it "should deconflict strict value" $ do
      let payload = A.encode BW.sampleValue
      let Right decodedAvro = A.decodeAvro BW.schema'Foo payload
      let Right deconflicted = A.deconflict BW.schema'Foo BR.schema'Foo decodedAvro

      A.fromAvro deconflicted `shouldBe` Success BR.sampleValue

  describe "Type C" $ do
    it "should deconflict complex type" $ do
      let payload = A.encode CW.sampleValue
      let decodedAvro = AL.decodeAvro CW.schema'Foo payload
      let res = AL.deconflict CW.schema'Foo CR.schema'Foo decodedAvro

      AL.fromLazyAvro res `shouldBe` Success CR.sampleValue

    it "should deconflict lazy container" $ do
      w <- liftIO $ A.encodeContainer [[ CW.sampleValue ]]
      AL.decodeContainer w `shouldBe` [ Right CR.sampleValue ]

    it "should deconflict lazy value" $ do
      let payload = A.encode CW.sampleValue
      let decodedAvro = AL.decodeAvro CW.schema'Foo payload
      let deconflicted = AL.deconflict CW.schema'Foo CR.schema'Foo decodedAvro

      AL.fromLazyAvro deconflicted `shouldBe` Success CR.sampleValue

    it "should deconflict strict container" $ do
      w <- A.encodeContainer [[CW.sampleValue]]
      A.decodeContainer w `shouldBe` [[CR.sampleValue]]

    it "should deconflict strict value" $ do
      let payload = A.encode CW.sampleValue
      let Right decodedAvro = A.decodeAvro CW.schema'Foo payload
      let Right deconflicted = A.deconflict CW.schema'Foo CR.schema'Foo decodedAvro

      A.fromAvro deconflicted `shouldBe` Success CR.sampleValue

  describe "Type D" $ do
    it "should deconflict complex type" $ do
      let payload = A.encode DW.sampleValue
      let decodedAvro = AL.decodeAvro DW.schema'Foo payload
      let res = AL.deconflict DW.schema'Foo DR.schema'Foo decodedAvro

      AL.fromLazyAvro res `shouldBe` Success DR.sampleValue

    it "should deconflict lazy container" $ do
      w <- liftIO $ A.encodeContainer [[ DW.sampleValue ]]
      AL.decodeContainer w `shouldBe` [ Right DR.sampleValue ]

    it "should deconflict lazy value" $ do
      let payload = A.encode DW.sampleValue
      let decodedAvro = AL.decodeAvro DW.schema'Foo payload
      let deconflicted = AL.deconflict DW.schema'Foo DR.schema'Foo decodedAvro

      AL.fromLazyAvro deconflicted `shouldBe` Success DR.sampleValue

    it "should deconflict strict container" $ do
      w <- A.encodeContainer [[DW.sampleValue]]
      A.decodeContainer w `shouldBe` [[DR.sampleValue]]

    it "should deconflict strict value" $ do
      let payload = A.encode DW.sampleValue
      let Right decodedAvro = A.decodeAvro DW.schema'Foo payload
      let Right deconflicted = A.deconflict DW.schema'Foo DR.schema'Foo decodedAvro

      A.fromAvro deconflicted `shouldBe` Success DR.sampleValue

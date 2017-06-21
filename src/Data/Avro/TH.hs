{-# LANGUAGE TemplateHaskell #-}
module Data.Avro.TH
( deriveAvro
, deriveFromAvro
)
where

import           Control.Monad              (join)
import           Data.Aeson                 (decode, eitherDecode)
import qualified Data.Aeson                 as J
import           Data.Avro                  hiding (decode, encode)
import qualified Data.Avro                  as A
import           Data.Avro.Schema           as S
import qualified Data.Avro.Types            as AT
import           Data.ByteString            (ByteString)
import           Data.Int
import           Data.List.NonEmpty
import           Data.Map                   (Map)
import           Data.Maybe                 (fromMaybe)
import           Data.Semigroup             ((<>))
import           Language.Haskell.TH        as TH
import           Language.Haskell.TH.Syntax

import qualified Data.ByteString.Lazy       as LBS
import qualified Data.ByteString.Lazy.Char8 as LBSC8
import           Data.Text                  (Text)
import qualified Data.Text                  as T

-- | Derives Avro from a given schema file.
-- Generates data types, FromAvro and ToAvro instances.
deriveAvro :: FilePath -> Q [Dec]
deriveAvro p = do
  qAddDependentFile p
  mbSchema <- runIO $ decodeSchema p
  case mbSchema of
    Left err     -> fail $ "Unable to generate AVRO for " <> p <> ": " <> err
    Right schema -> do
      let recs = getAllRecords schema
      types <- traverse genType recs
      fromAvros <- traverse genFromAvro recs
      toAvros <- traverse genToAvro recs
      return $ join types <> join fromAvros <> join toAvros

-- | Derives "read only" Avro from a given schema file.
-- Generates data types and FromAvro.
deriveFromAvro :: FilePath -> Q [Dec]
deriveFromAvro p = do
  qAddDependentFile p
  mbSchema <- runIO $ decodeSchema p
  case mbSchema of
    Left err     -> fail $ "Unable to generate AVRO for " <> p <> ": " <> err
    Right schema -> do
      let recs = getAllRecords schema
      types <- traverse genType recs
      fromAvros <- traverse genFromAvro recs
      return $ join types <> join fromAvros

genFromAvro :: Schema -> Q [Dec]
genFromAvro (S.Record (TN name) _ _ _ _ fs) =
  [d| instance FromAvro $(conT . mkTextName $ name) where
        fromAvro (AT.Record _ r) = $(genFromAvroFieldsExp (mkTextName name) fs) r
        fromAvro r               = $( [|\v -> badValue v $(mkTextLit name)|] ) r
  |]
genFromAvro _                             = return []

genFromAvroFieldsExp :: Name -> [Field] -> Q Exp
genFromAvroFieldsExp n (x:xs) =
  [| \r ->
    $(let extract fld = [| r .: T.pack $(mkTextLit (fldName fld))|]
          ctor = [| $(conE n) <$> $(extract x) |]
      in foldl (\exp fld -> [| $exp <*> $(extract fld) |]) ctor xs
     )
  |]

genToAvro :: Schema -> Q [Dec]
genToAvro s@(Record (TN name) _ _ _ _ fs) = do
  let sname = mkTextName (mkSchemaValueName name)
  sdef <- schemaDef sname
  idef <- toAvroInstance sname
  pure (sdef <> idef)
  where
    schemaDef sname =
      [d|
          $(varP sname) = fromMaybe undefined (J.decode (LBSC8.pack $(mkLit (LBSC8.unpack $ J.encode s)))) :: Schema
      |]
    toAvroInstance sname =
      [d| instance ToAvro $(conT . mkTextName $ name) where
            toAvro = $(genToAvroFieldsExp name sname fs)
            schema = pure $(varE sname)
      |]
    genToAvroFieldsExp prefix sname fs = [| \r -> record $(varE sname)
        $(let assign fld = [| T.pack $(mkTextLit (fldName fld)) .= $(varE . mkTextName $ mkFieldTextName prefix fld) r |]
          in listE $ assign <$> fs
        )
      |]

getAllRecords :: Schema -> [Schema]
getAllRecords r@(S.Record _ _ _ _ _ fs) = r : (fs >>= (getAllRecords . fldType))
getAllRecords (S.Array t)               = getAllRecords t
getAllRecords (S.Union (t1 :| [t2]) _)  = getAllRecords t1 <> getAllRecords t2
getAllRecords (S.Map t)                 = getAllRecords t
getAllRecords (S.Union (_ :| _:_:_) _)  = error "Unions with more than 2 elements are not yet supported"
getAllRecords _                       = []

genType :: Schema -> Q [Dec]
genType (S.Record (TN name) _ _ _ _ fs) = do
  fields <- traverse (mkField name) fs
  let dname = mkTextName $ mkDataTypeName name
  return [DataD [] dname [] Nothing [RecC dname fields] []]
genType _ = return []

mkSchemaValueName :: Text -> Text
mkSchemaValueName r = "schema'" <> r

mkDataTypeName :: Text -> Text
mkDataTypeName =
  updateFirst T.toUpper . T.takeWhileEnd (/='.')

mkFieldTextName :: Text -> Field -> Text
mkFieldTextName dn fld =
  updateFirst T.toLower dn <> updateFirst T.toUpper (fldName fld)

mkField :: Text -> Field -> Q VarBangType
mkField prefix field = do
  ftype <- mkFieldTypeName (fldType field)
  let fName = mkName $ T.unpack (mkFieldTextName prefix field)
  return (fName, defaultBang, ftype)

mkFieldTypeName :: S.Type -> Q TH.Type
mkFieldTypeName t = case t of
  S.Boolean                     -> [t| Bool |]
  S.Long                        -> [t| Int64 |]
  S.Int                         -> [t| Int |]
  S.Float                       -> [t| Float |]
  S.Double                      -> [t| Double |]
  S.Bytes                       -> [t| ByteString |]
  S.String                      -> [t| Text |]
  S.Union (Null :| [x]) _       -> [t| Maybe $(mkFieldTypeName x) |] -- AppT (ConT $ mkName "Maybe") (mkFieldTypeName x)
  S.Union (x :| [Null]) _       -> [t| Maybe $(mkFieldTypeName x) |] --AppT (ConT $ mkName "Maybe") (mkFieldTypeName x)
  S.Union (x :| [y]) _          -> [t| Either $(mkFieldTypeName x) $(mkFieldTypeName y) |] -- AppT (AppT (ConT (mkName "Either")) (mkFieldTypeName x)) (mkFieldTypeName y)
  S.Record (TN x) _ _ _ _ _     -> [t| $(conT . mkTextName . mkDataTypeName $ x) |]
  S.Map x                       -> [t| Map Text $(mkFieldTypeName x) |] --AppT (AppT (ConT (mkName "Map")) (ConT $ mkName "Text")) (mkFieldTypeName x)
  S.Array x                     -> [t| [$(mkFieldTypeName x)] |]--AppT (ConT $ Text "[]") (mkFieldTypeName x)
  S.NamedType (TN x)            -> [t| $(conT $ mkTextName (mkDataTypeName x))|] --ConT . mkName . T.unpack . mkDataTypeName $ x
  S.Fixed (TN x) _ _ _          -> [t| $(conT $ mkTextName (mkDataTypeName x))|] --ConT . mkName . T.unpack . mkDataTypeName $ x
  _                             -> error $ "Avro type is not supported: " <> show t

updateFirst :: (Text -> Text) -> Text -> Text
updateFirst f t =
  let (l, ls) = T.splitAt 1 t
  in f l <> ls

decodeSchema :: FilePath -> IO (Either String Schema)
decodeSchema p = eitherDecode <$> LBS.readFile p

defaultBang = Bang NoSourceUnpackedness NoSourceStrictness

mkTextName :: Text -> Name
mkTextName = mkName . T.unpack

mkLit = litE . StringL
mkTextLit = litE . StringL . T.unpack

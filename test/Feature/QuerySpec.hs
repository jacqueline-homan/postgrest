module Feature.QuerySpec where

import Test.Hspec
import Test.Hspec.Wai
import Test.Hspec.Wai.JSON
import Hasql as H
import Hasql.Postgres as H
import Control.Monad (void)
import Data.Text(Text)

import SpecHelper

testSet :: IO ()
testSet = do
  clearTable "items" >> clearTable "no_pk"
  createItems 15
  pool <- H.acquirePool pgSettings testPoolOpts
  void . liftIO $ H.session pool $ H.tx Nothing $
    mapM_ (H.unitEx . uncurry insertNoPk) [
        ("lick", "Fun"), ("trick", "funky")
      , ("barb", "foo"), ("BARD", "FOOD")
      ]

  where
    insertNoPk :: Text -> Text -> H.Stmt H.Postgres
    insertNoPk = [H.stmt|insert into "1".no_pk (a, b) values (?,?)|]

spec :: Spec
spec = beforeAll testSet . afterAll_ (clearTable "items") . around withApp $ do
  describe "Querying a nonexistent table" $
    it "causes a 404" $
      get "/faketable" `shouldRespondWith` 404

  describe "Filtering response" $ do
    it "matches with equality" $
      get "/items?id=eq.5"
        `shouldRespondWith` ResponseMatcher {
          matchBody    = Just [json| [{"id":5}] |]
        , matchStatus  = 200
        , matchHeaders = ["Content-Range" <:> "0-0/1"]
        }

    it "matches with like" $ do
      get "/no_pk?a=like.*ick&order=a.asc" `shouldRespondWith` [json|
        [{"a":"lick","b":"Fun"},{"a":"trick","b":"funky"}]|]
      get "/no_pk?b=like.f*&order=a.asc" `shouldRespondWith` [json|
        [{"a":"barb","b":"foo"},{"a":"trick","b":"funky"}]|]
      get "/no_pk?a=like.*AR*&order=a.asc" `shouldRespondWith` [json|
        [{"a":"BARD","b":"FOOD"}]|]

    it "matches with ilike" $ do
      get "/no_pk?b=ilike.fun*&order=a.asc" `shouldRespondWith` [json|
        [{"a":"lick","b":"Fun"},{"a":"trick","b":"funky"}]|]
      get "/no_pk?a=ilike.*AR*&order=a.asc" `shouldRespondWith` [json|
        [{"a":"BARD","b":"FOOD"},{"a":"barb","b":"foo"}]|]

  describe "ordering response" $ do
    it "by a column asc" $
      get "/items?id=lte.2&order=id.asc"
        `shouldRespondWith` ResponseMatcher {
          matchBody    = Just [json| [{"id":1},{"id":2}] |]
        , matchStatus  = 200
        , matchHeaders = ["Content-Range" <:> "0-1/2"]
        }
    it "by a column desc" $
      get "/items?id=lte.2&order=id.desc"
        `shouldRespondWith` ResponseMatcher {
          matchBody    = Just [json| [{"id":2},{"id":1}] |]
        , matchStatus  = 200
        , matchHeaders = ["Content-Range" <:> "0-1/2"]
        }

    it "without other constraints" $
      get "/items?order=asc.id" `shouldRespondWith` 200

  describe "Canonical location" $ do
    it "Sets Content-Location with alphabetized params" $
      get "/no_pk?b=eq.1&a=eq.1"
        `shouldRespondWith` ResponseMatcher {
          matchBody    = Just "[]"
        , matchStatus  = 200
        , matchHeaders = ["Content-Location" <:> "/no_pk?a=eq.1&b=eq.1"]
        }

    it "Omits question mark when there are no params" $
      get "/simple_pk"
        `shouldRespondWith` ResponseMatcher {
          matchBody    = Just "[]"
        , matchStatus  = 200
        , matchHeaders = ["Content-Location" <:> "/simple_pk"]
        }

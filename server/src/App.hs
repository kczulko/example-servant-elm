{-# LANGUAGE TypeOperators #-}

module App where

import           Control.Concurrent
import           Control.Monad.IO.Class
import           Data.Map
import           Network.Wai
import           Network.Wai.Application.Static (staticApp, defaultFileServerSettings)
import           Servant

import           Api

type WithAssets = Api :<|> Raw

withAssets :: Proxy WithAssets
withAssets = Proxy

assets :: Application
assets = staticApp $ defaultFileServerSettings "assets"

app :: IO Application
app = serve withAssets <$> server

server :: IO (Server WithAssets)
server = do
  db     <- mkDB
  return (apiServer db :<|> Tagged assets)

apiServer :: DB -> Server Api
apiServer db = listItems db :<|> getItem db :<|> postItem db :<|> deleteItem db

listItems :: DB -> Handler [ItemId]
listItems db = liftIO $ allItemIds db

getItem :: DB -> ItemId -> Handler Item
getItem db n = maybe (throwError err404) return =<< liftIO (lookupItem db n)

postItem :: DB -> String -> Handler ItemId
postItem db new = liftIO $ insertItem db new

-- fake DB

newtype DB = DB (MVar (Map ItemId String))

debug :: DB -> IO ()
debug (DB mvar) = readMVar mvar >>= print

mkDB :: IO DB
mkDB = DB <$> newMVar empty

insertItem :: DB -> String -> IO ItemId
insertItem (DB mvar) new = modifyMVar mvar $ \m -> do
  let newKey = case keys m of
        [] -> ItemId 0
        ks -> succ (maximum ks)
  return (insert newKey new m, newKey)

lookupItem :: DB -> ItemId -> IO (Maybe Item)
lookupItem (DB mvar) i = fmap (Item i) . Data.Map.lookup i <$> readMVar mvar

allItemIds :: DB -> IO [ItemId]
allItemIds (DB mvar) = keys <$> readMVar mvar

deleteItem :: MonadIO m => DB -> ItemId -> m ()
deleteItem (DB mvar) i = liftIO $ do
  modifyMVar_ mvar $ \m -> return (delete i m)
  return ()


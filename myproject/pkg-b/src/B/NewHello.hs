module B.NewHello where

import Data.Aeson ()
import Hello (hello)
import Prelude (IO, putStrLn)

newHello :: IO ()
newHello = do
  hello
  putStrLn "new hello"

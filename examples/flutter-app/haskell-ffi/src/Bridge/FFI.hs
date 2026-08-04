{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

module Bridge.FFI where

-- GHC requires C newtype constructors to be in scope while checking generated
-- foreign export declarations.
import Foreign.C.Types
  ( CChar (..)
  , CDouble (..)
  , CFloat (..)
  , CInt (..)
  , CLLong (..)
  , CShort (..)
  , CSChar (..)
  , CUChar (..)
  , CUInt (..)
  , CULLong (..)
  , CUShort (..)
  )
import Foreign.Ptr (FunPtr, Ptr)
import Foreign.StablePtr (StablePtr)
import qualified Lib

import Bridge.FFI.TH

$(deriveForeignExports
    [ foreignExport "haskell_add_int32" 'Lib.addInt32
    ])

{-# OPTIONS_GHC -fno-warn-orphans #-}
-- |
-- Module      : Data.Text.Lazy
-- Copyright   : (c) Bryan O'Sullivan 2009,
--               (c) Tom Harper 2008-2009,
--               (c) Duncan Coutts 2008
--
-- License     : BSD-style
-- Maintainer  : rtharper@aftereternity.co.uk, bos@serpentine.com,
--               duncan@haskell.org
-- Stability   : experimental
-- Portability : GHC
--
-- A time and space-efficient implementation of Unicode text using
-- lists of packed arrays.  This representation is suitable for high
-- performance use and for streaming large quantities of data.  It
-- provides a means to manipulate a large body of text without
-- requiring that the entire content be resident in memory.
--
-- Some operations, such as 'concat', 'append', 'reverse' and 'cons',
-- have better complexity than their "Data.Text" equivalents, due to
-- optimisations resulting from the list spine structure. And for
-- other operations lazy 'Text's are usually within a few percent of
-- strict ones, but with better heap usage. For data larger than
-- available memory, or if you have tight memory constraints, this
-- module will be the only option.
--
-- This module is intended to be imported @qualified@, to avoid name
-- clashes with "Prelude" functions.  eg.
--
-- > import qualified Data.Text.Lazy as B

module Data.Text.Lazy
    (
      Text
    -- * Creation and elimination
    , pack
    , unpack
    , singleton
    , empty

    -- * Basic interface
    , cons
    , snoc
    , append
    , uncons
    , head
    , last
    , tail
    , init
    , null
    , length

    -- * Transformations
    , map
    , intercalate
    , intersperse
    -- , transpose
    -- , reverse

    -- * Folds
    , foldl
    , foldl'
    , foldl1
    , foldl1'
    , foldr
    , foldr1

    -- ** Special folds
    -- , concat
    -- , concatMap
    -- , any
    -- , all
    -- , maximum
    -- , minimum

    -- * Construction

    -- ** Scans
    -- , scanl
    -- , scanl1
    -- , scanr
    -- , scanr1

    -- ** Accumulating maps
    -- , mapAccumL
    -- , mapAccumR

    -- ** Generation and unfolding
    -- , replicate
    -- , unfoldr
    -- , unfoldrN

    -- * Substrings

    -- ** Breaking strings
    -- , take
    -- , drop
    -- , takeWhile
    -- , dropWhile
    , splitAt
    -- , span
    -- , break
    -- , group
    -- , groupBy
    -- , inits
    -- , tails

    -- ** Breaking into many substrings
    -- , split
    -- , splitWith
    -- , breakSubstring

    -- ** Breaking into lines and words
    -- , lines
    --, lines'
    -- , words
    -- , unlines
    -- , unwords

    -- * Predicates
    -- , isPrefixOf
    -- , isSuffixOf
    -- , isInfixOf

    -- * Searching
    -- , elem
    -- , filter
    -- , find
    -- , partition

    -- , findSubstring
    
    -- * Indexing
    -- , index
    -- , findIndex
    -- , findIndices
    -- , elemIndex
    -- , elemIndices
    -- , count

    -- * Zipping and unzipping
    -- , zipWith

    -- -* Ordered text
    -- , sort
    ) where

import Prelude (Char, Bool(..), Functor(..), Int, Maybe(..), String,
                Eq(..), Ord(..), (++),
                Read(..), Show(..),
                (&&), (||), (+), (-), (.), ($),
                fromIntegral, not, return, otherwise)
import qualified Prelude as P
import Data.Int (Int64)
import qualified Data.List as L
import Data.String (IsString(..))
import qualified Data.Text as T
import qualified Data.Text.Fusion as S
import qualified Data.Text.Fusion.Internal as S
import qualified Data.Text.Unsafe as T
import Data.Text.Lazy.Fusion
import Data.Text.Lazy.Internal

instance Eq Text where
    t1 == t2 = stream t1 == stream t2
    {-# INLINE (==) #-}

instance Ord Text where
    compare t1 t2 = compare (stream t1) (stream t2)
    {-# INLINE compare #-}

instance Show Text where
    showsPrec p ps r = showsPrec p (unpack ps) r

instance Read Text where
    readsPrec p str = [(pack x,y) | (x,y) <- readsPrec p str]

instance IsString Text where
    fromString = pack

-- | /O(n)/ Convert a 'String' into a 'Text'.
--
-- This function is subject to array fusion.
pack :: String -> Text
pack s = unstream (S.streamList s)
{-# INLINE [1] pack #-}

-- | /O(n)/ Convert a 'Text' into a 'String'.
-- Subject to array fusion.
unpack :: Text -> String
unpack t = S.unstreamList (stream t)
{-# INLINE [1] unpack #-}

singleton :: Char -> Text
singleton c = Chunk (T.singleton c) Empty
{-# INLINE [1] singleton #-}

{-# RULES
"LAZY TEXT singleton -> fused" [~1] forall c.
    singleton c = unstream (S.singleton c)
"LAZY TEXT singleton -> unfused" [1] forall c.
    unstream (S.singleton c) = singleton c
  #-}

cons :: Char -> Text -> Text
cons c t = Chunk (T.singleton c) t
{-# INLINE [1] cons #-}

{-# RULES
"LAZY TEXT cons -> fused" [~1] forall c t.
    cons c t = unstream (S.cons c (stream t))
"LAZY TEXT cons -> unfused" [1] forall c t.
    unstream (S.cons c (stream t)) = cons c t
 #-}

snoc :: Text -> Char -> Text
snoc t c = foldrChunks Chunk (singleton c) t
{-# INLINE [1] snoc #-}

{-# RULES
"LAZY TEXT snoc -> fused" [~1] forall t c.
    snoc t c = unstream (S.snoc (stream t) c)
"LAZY TEXT snoc -> unfused" [1] forall t c.
    unstream (S.snoc (stream t) c) = snoc t c
 #-}

-- | /O(n\/c)/ Appends one 'Text' to another.  Subject to array
-- fusion.
append :: Text -> Text -> Text
append xs ys = foldrChunks Chunk ys xs
{-# INLINE [1] append #-}

{-# RULES
"LAZY TEXT append -> fused" [~1] forall t1 t2.
    append t1 t2 = unstream (S.append (stream t1) (stream t2))
"LAZY TEXT append -> unfused" [1] forall t1 t2.
    unstream (S.append (stream t1) (stream t2)) = append t1 t2
 #-}

-- | /O(1)/ Returns the first character and rest of a 'Text', or
-- 'Nothing' if empty. Subject to array fusion.
uncons :: Text -> Maybe (Char, Text)
uncons Empty = Nothing
uncons (Chunk t ts) =
    Just (T.unsafeHead t,
          if T.length t == 1 then ts else Chunk (T.unsafeTail t) ts)
{-# INLINE uncons #-}

-- | /O(1)/ Returns the first character of a 'Text', which must be
-- non-empty.  Subject to array fusion.
head :: Text -> Char
head t = S.head (stream t)
{-# INLINE head #-}

-- | /O(1)/ Returns all characters after the head of a 'Text', which
-- must be non-empty.  Subject to array fusion.
tail :: Text -> Text
tail (Chunk t ts) = chunk (T.tail t) ts
tail Empty        = emptyError "tail"
{-# INLINE [1] tail #-}

{-# RULES
"LAZY TEXT tail -> fused" [~1] forall t.
    tail t = unstream (S.tail (stream t))
"LAZY TEXT tail -> unfused" [1] forall t.
    unstream (S.tail (stream t)) = tail t
 #-}

-- | /O(1)/ Returns all but the last character of a 'Text', which must
-- be non-empty.  Subject to array fusion.
init :: Text -> Text
init (Chunk t0 ts0) = go t0 ts0
    where go t (Chunk t' ts) = Chunk t (go t' ts)
          go t Empty         = chunk (T.init t) Empty
init Empty = emptyError "init"
{-# INLINE [1] init #-}

{-# RULES
"LAZY TEXT init -> fused" [~1] forall t.
    init t = unstream (S.init (stream t))
"LAZY TEXT init -> unfused" [1] forall t.
    unstream (S.init (stream t)) = init t
 #-}

-- | /O(1)/ Tests whether a 'Text' is empty or not.  Subject to array
-- fusion.
null :: Text -> Bool
null Empty = True
null _     = False
{-# INLINE [1] null #-}

{-# RULES
"LAZY TEXT null -> fused" [~1] forall t.
    null t = S.null (stream t)
"LAZY TEXT null -> unfused" [1] forall t.
    S.null (stream t) = null t
 #-}

-- | /O(1)/ Returns the last character of a 'Text', which must be
-- non-empty.  Subject to array fusion.
last :: Text -> Char
last Empty        = emptyError "last"
last (Chunk t ts) = go t ts
    where go _ (Chunk t' ts') = go t' ts'
          go t' Empty         = T.last t'
{-# INLINE [1] last #-}

{-# RULES
"LAZY TEXT last -> fused" [~1] forall t.
    last t = S.last (stream t)
"LAZY TEXT last -> unfused" [1] forall t.
    S.last (stream t) = last t
  #-}

length :: Text -> Int64
length = foldlChunks go 0
    where go l t = l + fromIntegral (T.length t)
{-# INLINE [1] length #-}

{-# RULES
"LAZY TEXT length -> fused" [~1] forall t.
    length t = S.length64 (stream t)
"LAZY TEXT length -> unfused" [1] forall t.
    S.length64 (stream t) = length t
 #-}

-- | /O(n)/ 'map' @f @xs is the 'Text' obtained by applying @f@ to
-- each element of @xs@.  Subject to array fusion.
map :: (Char -> Char) -> Text -> Text
map f t = unstream (S.map f (stream t))
{-# INLINE [1] map #-}

-- | /O(n)/ The 'intercalate' function takes a 'Text' and a list of
-- 'Text's and concatenates the list after interspersing the first
-- argument between each element of the list.
intercalate :: Text -> [Text] -> Text
intercalate t ts = unstream (S.intercalate (stream t) (L.map stream ts))
{-# INLINE intercalate #-}

-- | /O(n)/ The 'intersperse' function takes a character and places it
-- between the characters of a 'Text'.  Subject to array fusion.
intersperse     :: Char -> Text -> Text
intersperse c t = unstream (S.intersperse c (stream t))
{-# INLINE intersperse #-}

-- | /O(n)/ 'foldl', applied to a binary operator, a starting value
-- (typically the left-identity of the operator), and a 'Text',
-- reduces the 'Text' using the binary operator, from left to right.
-- Subject to array fusion.
foldl :: (b -> Char -> b) -> b -> Text -> b
foldl f z t = S.foldl f z (stream t)
{-# INLINE foldl #-}

-- | /O(n)/ A strict version of 'foldl'.
-- Subject to array fusion.
foldl' :: (b -> Char -> b) -> b -> Text -> b
foldl' f z t = S.foldl' f z (stream t)
{-# INLINE foldl' #-}

-- | /O(n)/ A variant of 'foldl' that has no starting value argument,
-- and thus must be applied to a non-empty 'Text'.  Subject to array
-- fusion.
foldl1 :: (Char -> Char -> Char) -> Text -> Char
foldl1 f t = S.foldl1 f (stream t)
{-# INLINE foldl1 #-}

-- | /O(n)/ A strict version of 'foldl1'.
-- Subject to array fusion.
foldl1' :: (Char -> Char -> Char) -> Text -> Char
foldl1' f t = S.foldl1' f (stream t)
{-# INLINE foldl1' #-}

-- | /O(n)/ 'foldr', applied to a binary operator, a starting value
-- (typically the right-identity of the operator), and a 'Text',
-- reduces the 'Text' using the binary operator, from right to left.
-- Subject to array fusion.
foldr :: (Char -> b -> b) -> b -> Text -> b
foldr f z t = S.foldr f z (stream t)
{-# INLINE foldr #-}

-- | /O(n)/ A variant of 'foldr' that has no starting value argument, and
-- thust must be applied to a non-empty 'Text'.  Subject to array
-- fusion.
foldr1 :: (Char -> Char -> Char) -> Text -> Char
foldr1 f t = S.foldr1 f (stream t)
{-# INLINE foldr1 #-}

-- | /O(n)/ 'splitAt' @n t@ returns a pair whose first element is a
-- prefix of @t@ of length @n@, and whose second is the remainder of
-- the string. It is equivalent to @('take' n t, 'drop' n t)@.
splitAt :: Int -> Text -> (Text, Text)
splitAt = loop
  where loop _ Empty      = (empty, empty)
        loop n t | n <= 0 = (empty, t)
        loop n (Chunk t ts)
             | n < len   = let (ts',ts'') = T.splitAt n t
                           in (Chunk ts' Empty, Chunk ts'' Empty)
             | otherwise = let (ts',ts'') = loop (n - len) ts
                           in (Chunk t ts', ts'')
             where len = T.length t

emptyError :: String -> a
emptyError fun = P.error ("Data.Text.Lazy." ++ fun ++ ": empty input")

{-# LANGUAGE CPP, MagicHash, ForeignFunctionInterface, NoImplicitPrelude,
             BangPatterns, UnboxedTuples, UnliftedFFITypes #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}


#include "MachDeps.h"

module New3.GHC.Integer.Natural where

import Prelude hiding (Integer, abs, pi, sum, rem) -- (all, error, otherwise, return, show, succ, (++))

import Data.Bits

import GHC.Prim
import GHC.Types
import GHC.Tuple ()
#if WORD_SIZE_IN_BITS < 64
import GHC.IntWord64
#endif

import Numeric (showHex) -- TODO: Remove when its working.
import Debug.Trace

import New3.GHC.Integer.Prim
import New3.GHC.Integer.Sign
import New3.GHC.Integer.StrictPrim
import New3.GHC.Integer.Type
import New3.GHC.Integer.WordArray

#if !defined(__HADDOCK__)

--------------------------------------------------------------------------------

encodeDoubleNatural :: Natural -> Int# -> Double#
encodeDoubleNatural !(Natural n arr) s
    | isTrue# (s +# (unboxInt (n * 64)) ># 2500#) = 1.0## /## 0.0##
    | isTrue# (s -# (unboxInt (n * 64)) <# -2500#) = 0.0##
    | otherwise = (+##)
            (encodeDouble# (unboxWord (indexWordArray arr (n - 1))) (s +# 64# *# unboxInt (n - 1)))
            (encodeDouble# (unboxWord (indexWordArray arr (n - 2))) (s +# 64# *# unboxInt (n - 2)))

foreign import ccall unsafe "__word_encodeDouble"
        encodeDouble# :: Word# -> Int# -> Double#

andNatural :: Natural -> Natural -> Natural
andNatural (Natural n1 arr1) (Natural n2 arr2) = andArray (min n1 n2) arr1 arr2

andArray :: Int -> WordArray -> WordArray -> Natural
andArray n arr1 arr2 = runStrictPrim $ do
    marr <- newWordArray n
    loop1 marr 0
    narr <- unsafeFreezeWordArray marr
    nlen <- loop2 narr (n - 1)
    return $! Natural nlen narr
  where
    loop1 !marr !i
        | i < n = do
                x <- indexWordArrayM arr1 i
                y <- indexWordArrayM arr2 i
                writeWordArray marr i (x .&. y)
                loop1 marr (i + 1)
        | otherwise = return ()
    loop2 !narr !i
        | i < 0 = return 0
        | indexWordArray narr i == 0 = loop2 narr (i - 1)
        | otherwise = return (i + 1)

orNatural :: Natural -> Natural -> Natural
orNatural (Natural n1 arr1) (Natural n2 arr2) = orArray n1 arr1 n2 arr2

orNaturalW :: Natural -> Word -> Natural
orNaturalW !(Natural !n !arr) !w = runStrictPrim $ do
    marr <- newWordArray n
    copyWordArray marr 1 arr 1 (n - 1)
    x <- indexWordArrayM arr 0
    writeWordArray marr 0 (w .|. x)
    narr <- unsafeFreezeWordArray marr
    return $! Natural n narr

orArray :: Int -> WordArray -> Int -> WordArray -> Natural
orArray !n1 !arr1 !n2 !arr2
    | n1 < n2 = orArray n2 arr2 n1 arr1
    | otherwise = runStrictPrim $ do
        marr <- newWordArray n1
        loop1 marr 0
        narr <- unsafeFreezeWordArray marr
        return $! Natural n1 narr
  where
    loop1 !marr !i
        | i < n2 = do
                x <- indexWordArrayM arr1 i
                y <- indexWordArrayM arr2 i
                writeWordArray marr i (x .|. y)
                loop1 marr (i + 1)
        | otherwise = loop2 marr i
    loop2 !marr !i
        | i < n1 = do
                -- TODO : Use copyArray here?
                x <- indexWordArrayM arr1 i
                writeWordArray marr i x
                loop2 marr (i + 1)
        | otherwise = return ()


xorArray :: Int -> WordArray -> Int -> WordArray -> Natural
xorArray !n1 !arr1 !n2 !arr2
    | n1 < n2 = xorArray n2 arr2 n1 arr1
    | otherwise = runStrictPrim $ do
        marr <- newWordArray n1
        loop1 marr 0
        narr <- unsafeFreezeWordArray marr
        -- TODO : Test this and then optimize.
        finalizeNatural n1 narr
  where
    loop1 !marr !i
        | i < n2 = do
                x <- indexWordArrayM arr1 i
                y <- indexWordArrayM arr2 i
                writeWordArray marr i (xor x y)
                loop1 marr (i + 1)
        | otherwise = loop2 marr i
    loop2 !marr !i
        | i < n1 = do
                -- TODO : Use copyArray here?
                x <- indexWordArrayM arr1 i
                writeWordArray marr i x
                loop2 marr (i + 1)
        | otherwise = return ()


shiftLNatural :: Natural -> Int -> Natural
shiftLNatural !nat@(Natural !n !arr) !i
    | i <= 0 = nat
    | i < WORD_SIZE_IN_BITS =
            smallShiftLArray n arr (# i, WORD_SIZE_IN_BITS - i #)
    | otherwise = do
            let (!q, !r) = quotRem i WORD_SIZE_IN_BITS
            if r == 0
                then wordShiftLArray n arr q
                else largeShiftLArray n arr (# q, r, WORD_SIZE_IN_BITS - r #)

smallShiftLArray :: Int -> WordArray -> (# Int, Int #) -> Natural
smallShiftLArray !n !arr (# !si, !sj #) = runStrictPrim $ do
    marr <- newWordArray (succ n)
    nlen <- loop marr 0 0
    narr <- unsafeFreezeWordArray marr
    return $! Natural nlen narr
  where
    loop !marr !i !mem
        | i < n =  do
            x <- indexWordArrayM arr i
            writeWordArray marr i ((unsafeShiftL x si) .|. mem)
            loop marr (i + 1) (unsafeShiftR x sj)
        | mem /= 0 = do
            writeWordArray marr i mem
            return $ i + 1
        | otherwise = return n

-- | TODO : Use copy here? Check benchmark results.
wordShiftLArray :: Int -> WordArray -> Int -> Natural
wordShiftLArray !n !arr !q = runStrictPrim $ do
    marr <- newWordArray (n + q)
    loop1 marr 0
    narr <- unsafeFreezeWordArray marr
    return $! Natural (n + q) narr
  where
    loop1 !marr !i
        | i < q = do
            writeWordArray marr i 0
            loop1 marr (i + 1)
        | otherwise = loop2 marr 0
    loop2 !marr !i
        | i < n =  do
            x <- indexWordArrayM arr i
            writeWordArray marr (q + i) x
            loop2 marr (i + 1)
        | otherwise = return ()

largeShiftLArray :: Int -> WordArray-> (# Int, Int, Int #) -> Natural
largeShiftLArray !n !arr (# !q, !si, !sj #) = runStrictPrim $ do
    marr <- newWordArray (n + q + 1)
    setWordArray marr 0 q 0
    nlen <- loop1 marr 0 0
    narr <- unsafeFreezeWordArray marr
    return $! Natural nlen narr
  where
    loop1 !marr !i !mem
        | i < n =  do
            x <- indexWordArrayM arr i
            writeWordArray marr (q + i) ((unsafeShiftL x si) .|. mem)
            loop1 marr (i + 1) (unsafeShiftR x sj)
        | mem /= 0 = do
            writeWordArray marr (q + i) mem
            return (q + i + 1)
        | otherwise = return (q + i)


shiftRNatural :: Natural -> Int -> Natural
shiftRNatural !(Natural !n !arr) !i
    | i < WORD_SIZE_IN_BITS =
            smallShiftRArray n arr (# i, WORD_SIZE_IN_BITS - i #)
    | otherwise = do
            let (!q, !r) = quotRem i WORD_SIZE_IN_BITS
            if q >= n
                then zeroNatural
                else if r == 0
                    then wordShiftRArray n arr q
                    else largeShiftRArray n arr (# q, r, WORD_SIZE_IN_BITS - r #)


smallShiftRArray :: Int -> WordArray -> (# Int, Int #) -> Natural
smallShiftRArray !n !arr (# !si, !sj #) = runStrictPrim $ do
    marr <- newWordArray n
    loop marr (n - 1) 0
    narr <- unsafeFreezeWordArray marr
    return $! Natural n narr
  where
    loop !marr !i !mem
        | i >= 0 =  do
            x <- indexWordArrayM arr i
            writeWordArray marr i ((unsafeShiftR x si) .|. mem)
            loop marr (i - 1) (unsafeShiftL x sj)
        | otherwise = return ()

wordShiftRArray :: Int -> WordArray -> Int -> Natural
wordShiftRArray !n !arr !q = runStrictPrim $ do
    marr <- newWordArray (n - q)
    copyWordArray marr 0 arr q (n - q)
    narr <- unsafeFreezeWordArray marr
    return $! Natural (n - q) narr

largeShiftRArray :: Int -> WordArray-> (# Int, Int, Int #) -> Natural
largeShiftRArray !n !arr (# !q, !si, !sj #) = runStrictPrim $ do
    marr <- newWordArray (n - q)
    loop marr (n - q - 1) 0
    narr <- unsafeFreezeWordArray marr
    return $! Natural (n - q) narr
  where
    loop !marr !i !mem
        | i >= 0 =  do
            x <- indexWordArrayM arr (q + i)
            writeWordArray marr i ((unsafeShiftR x si) .|. mem)
            loop marr (i - 1) (unsafeShiftL x sj)
        | otherwise = return ()

{-# INLINE plusNaturalW #-}
plusNaturalW :: Natural -> Word -> Natural
plusNaturalW !(Natural !n !arr) !w = runStrictPrim $ do
    marr <- newWordArray (succ n)
    x <- indexWordArrayM arr 0
    let (# !cry, !sm #) = plusWord2 x w
    writeWordArray marr 0 sm
    nlen <- loop1 marr 1 cry
    narr <- unsafeFreezeWordArray marr
    return $! Natural nlen narr
  where
    loop1 !marr !i !carry
        | carry == 0 = loop2 marr i
        | i < n =  do
            x <- indexWordArrayM arr i
            let (# !cry, !sm #) = plusWord2 x carry
            writeWordArray marr i sm
            loop1 marr (i + 1) cry
        | otherwise = do
            writeWordArray marr i carry
            return $ n + 1
    loop2 !marr !i
        | i < n =  do
            x <- indexWordArrayM arr i
            writeWordArray marr i x
            loop2 marr (i + 1)
        | otherwise = return i

{-# NOINLINE plusNatural #-}
plusNatural :: Natural -> Natural -> Natural
plusNatural !a@(Natural !n1 !arr1) !b@(Natural !n2 !arr2)
    | n1 < n2 = plusNatural b a
    | otherwise = runStrictPrim $ do
        marr <- newWordArray (succ n1)
        nlen <- loop1 marr 0 0
        narr <- unsafeFreezeWordArray marr
        return $! Natural nlen narr
  where
    loop1 !marr !i !carry
        | i < n2 = do
            x <- indexWordArrayM arr1 i
            y <- indexWordArrayM arr2 i
            let (# !cry, !sm #) = plusWord2C x y carry
            writeWordArray marr i sm
            loop1 marr (i + 1) cry
        | otherwise = loop2 marr i carry
    loop2 !marr !i !carry
        | carry == 0 = loop3 marr i
        | i < n1 = do
            x <- indexWordArrayM arr1 i
            let (# !cry, !sm #) = plusWord2 x carry
            writeWordArray marr i sm
            loop2 marr (i + 1) cry
        | otherwise = do
            writeWordArray marr i carry
            return (i + 1)
    loop3 !marr !i
        | i < n1 = do
            x <- indexWordArrayM arr1 i
            writeWordArray marr i x
            loop3 marr (i + 1)
        | otherwise = return i


{-# INLINE minusNaturalW #-}
minusNaturalW :: Natural -> Word -> Natural
minusNaturalW !(Natural !n !arr) !w = runStrictPrim $ do
    marr <- newWordArray (succ n)
    x <- indexWordArrayM arr 0
    let (# !c, !d #) = minusWord2 x w
    writeWordArray marr 0 d
    nlen <- loop1 marr 1 c
    narr <- unsafeFreezeWordArray marr
    finalizeNatural nlen narr
  where
    loop1 !marr !i !carry
        | carry == 0 = loop2 marr i
        | i < n =  do
            x <- indexWordArrayM arr i
            let (# !c, !d #) = minusWord2 x carry
            writeWordArray marr i d
            loop1 marr (i + 1) c
        | otherwise = do
            writeWordArray marr i carry
            return $ n + 1
    loop2 !marr !i
        | i < n =  do
            x <- indexWordArrayM arr i
            writeWordArray marr i x
            loop2 marr (i + 1)
        | otherwise = return n


{-# INLINE minusNatural #-}
minusNatural :: Natural -> Natural -> Natural
minusNatural !a@(Natural !n1 !arr1) !b@(Natural !n2 !arr2)
    | n1 < n2 = plusNatural b a
    | otherwise = runStrictPrim $ do
        marr <- newWordArray (succ n1)
        nlen <- loop1 marr 0 0
        narr <- unsafeFreezeWordArray marr
        finalizeNatural nlen narr
  where
    loop1 !marr !i !carry
        | i < n2 = do
            x <- indexWordArrayM arr1 i
            y <- indexWordArrayM arr2 i
            let (# !c, !d #) = minusWord2C x y carry
            writeWordArray marr i d
            loop1 marr (i + 1) c
        | otherwise = loop2 marr i carry
    loop2 !marr !i !carry
        | carry == 0 = loop3 marr i
        | i < n1 = do
            x <- indexWordArrayM arr1 i
            let (# !c, !d #) = minusWord2 x carry
            writeWordArray marr i d
            loop2 marr (i + 1) c
        | otherwise = do
            writeWordArray marr i carry
            return (i + 1)
    loop3 !marr !i
        | i < n1 = do
            x <- indexWordArrayM arr1 i
            writeWordArray marr i x
            loop3 marr (i + 1)
        | otherwise = return i


{-# NOINLINE timesNaturalW #-}
timesNaturalW :: Natural -> Word -> Natural
timesNaturalW !(Natural !n !arr) !w = runStrictPrim $ do
    marr <- newWordArray (succ n)
    nlen <- loop marr 0 0
    narr <- unsafeFreezeWordArray marr
    return $! Natural nlen narr
  where
    loop !marr !i !carry
        | i < n = do
            x <- indexWordArrayM arr i
            let (# !c, !p #) = timesWord2C x w carry
            writeWordArray marr i p
            loop marr (i + 1) c
        | carry /= 0 = do
            writeWordArray marr i carry
            return (i + 1)
        | otherwise = return i

{-# NOINLINE timesNatural #-}
timesNatural :: Natural -> Natural -> Natural
timesNatural !a@(Natural !n1 !arr1) !b@(Natural !n2 !arr2)
    | n1 < n2 = timesNatural b a
    | otherwise = runStrictPrim $ do
        psum <- newPlaceholderWordArray
        outerLoop 0 psum 0
  where
    outerLoop !psumLen !psum !s2
        | s2 < n2 = do
            w <- indexWordArrayM arr2 s2
            if w == 0
                then outerLoop psumLen psum (succ s2)
                else do
                    newPsumLen <- return (succ (max psumLen (n1 + succ s2)))
                    marr <- cloneWordArrayExtend psumLen psum newPsumLen
                    possLen <- innerLoop1 marr psumLen psum 0 s2 w 0
                    narr <- unsafeFreezeWordArray marr
                    outerLoop possLen narr (succ s2)
        | otherwise =
            return $! Natural psumLen psum

    innerLoop1 !marr !pn !psum !s1 !s2 !hw !carry
        | s1 + s2 < pn = do
            ps <- indexWordArrayM psum (s1 + s2)
            x <- indexWordArrayM arr1 s1
            let (# !hc, !hp #) = timesWord2CC x hw carry ps
            writeWordArray marr (s1 + s2) hp
            innerLoop1 marr pn psum (s1 + 1) s2 hw hc
        | otherwise = innerLoop2 marr pn psum s1 s2 hw carry

    innerLoop2 !marr !pn !psum !s1 !s2 !hw !carry
        | s1 < n1 = do
            x <- indexWordArrayM arr1 s1
            let (# !hc, !hp #) = timesWord2C x hw carry
            writeWordArray marr (s1 + s2) hp
            innerLoop2 marr pn psum (s1 + 1) s2 hw hc
        | carry /= 0 = do
            writeWordArray marr (s1 + s2) carry
            return (s1 + s2 + 1)
        | otherwise = return (s1 + s2)

{-# NOINLINE timesNaturalNew #-}
timesNaturalNew :: Natural -> Natural -> Natural
timesNaturalNew !a@(Natural !n1 !arr1) !b@(Natural !n2 !arr2)
    | n1 < n2 = timesNaturalNew b a
    | otherwise = runStrictPrim $ do
        maxOutLen <- return (1 + n1 + n2)
        psum <- newWordArray maxOutLen
        writeWordArray psum 0 0
        outerLoop 0 0 psum
  where
    outerLoop !s2 !psumLen !psum
        | s2 < n2 = do
            w <- indexWordArrayM arr2 s2
            if w == 0
                then do
                    -- WTF? Need this to avoid laziness screwing things up!
                    _ <- innerLoop2 psumLen psum psumLen s2 s2 w 0
                    outerLoop (succ s2) psumLen psum

                else do
                    possLen <- innerLoop1 psumLen psum 0 s2 s2 w 0
                    outerLoop (succ s2) possLen psum
        | otherwise = do
            narr <- unsafeFreezeWordArray psum
            return $! Natural psumLen narr

    innerLoop1 !pn !psum !s1 !d1 !s2 !w !carry
        | d1 < pn = do
            ps <- readWordArray psum d1
            x <- indexWordArrayM arr1 s1
            let (# !cry, !prod #) = timesWord2CC x w carry ps
            writeWordArray psum d1 prod
            innerLoop1 pn psum (s1 + 1) (d1 + 1) s2 w cry
        | otherwise = innerLoop2 pn psum s1 d1 s2 w carry

    innerLoop2 !pn !psum !s1 !d1 !s2 !w !carry
        | s1 < n1 = do
            x <- indexWordArrayM arr1 s1
            let (# !cry, !prod #) = timesWord2C x w carry
            writeWordArray psum d1 prod
            innerLoop2 pn psum (s1 + 1) (d1 + 1) s2 w cry
        | carry /= 0 = do
            writeWordArray psum d1 carry
            return $! d1 + 1
        | otherwise = return d1


{-# NOINLINE timesNaturalNewest #-}
timesNaturalNewest :: Natural -> Natural -> Natural
timesNaturalNewest !a@(Natural !n1 !arr1) !b@(Natural !n2 !arr2)
    | n1 < n2 = timesNaturalNewest b a
    | otherwise = runStrictPrim $ do
        maxOutLen <- return (1 + n1 + n2)
        marr <- newWordArray maxOutLen
        len <- preLoop marr
        narr <- unsafeFreezeWordArray marr
        return $! Natural len narr
  where
    preLoop marr = do
        x <- indexWordArrayM arr1 0
        y <- indexWordArrayM arr2 0
        let (# cry, prod #) = timesWord2 x y
        writeWordArray marr 0 prod
        outerLoop1 1 marr 0 cry

    outerLoop1 !nx !marr !carryhi !carrylo
        | nx < n2 = do
            (cryhi, crylo, sum) <- innerLoop1xi nx 0 0 carryhi carrylo
            writeWordArray marr nx sum
            outerLoop1 (nx + 1) marr cryhi crylo
        | otherwise = outerLoop1a nx marr carryhi carrylo

    outerLoop1a !nx !marr !carryhi !carrylo
        | nx < n1 - 1 = do
            (cryhi, crylo, sum) <- innerLoop1yi nx 0 0 carryhi carrylo
            writeWordArray marr nx sum
            outerLoop1a (nx + 1) marr cryhi crylo
        | otherwise = outerLoop2 nx marr carryhi carrylo

    innerLoop1xi !xi !yi !carryhi !carrylo !sum
        | xi >= 0 = do
            x <- indexWordArrayM arr1 xi
            y <- indexWordArrayM arr2 yi
            let (# !cry0, !prod #) = timesWord2 x y
                (# !cry1, !sum1 #) = plusWord2 prod sum
                (# !tcryhi, !crylo #) = plusWord2C carrylo cry0 cry1
                !cryhi = plusWord carryhi tcryhi
            innerLoop1xi (xi - 1) (yi + 1) cryhi crylo sum1
        | otherwise = return $! (carryhi, carrylo, sum)

    innerLoop1yi !xi !yi !carryhi !carrylo !sum
        | yi < n2 = do
            x <- indexWordArrayM arr1 xi
            y <- indexWordArrayM arr2 yi
            let (# !cry0, !prod #) = timesWord2 x y
                (# !cry1, !sum1 #) = plusWord2 prod sum
                (# !tcryhi, !crylo #) = plusWord2C carrylo cry0 cry1
                !cryhi = plusWord carryhi tcryhi
            innerLoop1yi (xi - 1) (yi + 1) cryhi crylo sum1
        | otherwise = return $! (carryhi, carrylo, sum)

    outerLoop2 !nx !marr !carryhi !carrylo
        | nx < n1 + n2 - 1 = do
            (cryhi, crylo, sum) <- innerLoop2 (n1 - 1) (nx - n1 + 1) 0 carryhi carrylo
            writeWordArray marr nx sum
            outerLoop2 (nx + 1) marr cryhi crylo
        | carrylo /= 0 = do
            writeWordArray marr nx carrylo
            return $! nx + 1
        | otherwise = return $! nx

    innerLoop2 !xi !yi !carryhi !carrylo !sum
        | yi < n2 = do
            x <- indexWordArrayM arr1 xi
            y <- indexWordArrayM arr2 yi
            let (# !cry0, !prod #) = timesWord2 x y
                (# !cry1, !sum1 #) = plusWord2 prod sum
                (# !tcryhi, !crylo #) = plusWord2C carrylo cry0 cry1
                !cryhi = plusWord carryhi tcryhi
            innerLoop2 (xi - 1) (yi + 1) cryhi crylo sum1
        | otherwise = do return $! (carryhi, carrylo, sum)


quotRemNaturalW :: Natural -> Word -> (Natural, Word)
quotRemNaturalW !(Natural !n !arr) !w = runStrictPrim $ do
    qlen <- return $! if w >= indexWordArray arr (n - 1) then n - 1 else n
    qmarr <- newWordArray qlen
    rem <- loop (n - 1) qmarr 0
    qarr <- unsafeFreezeWordArray qmarr
    return $! (Natural qlen qarr, rem)
  where
    loop i qmarr rem
        | i >= 0 = do
            x <- indexWordArrayM arr i
            let (# q, r #) = quotRemWord2 rem x w
            writeWordArray qmarr i q
            loop (i - 1) qmarr r
        | otherwise = return rem

{-
https://www.khanacademy.org/math/arithmetic/multiplication-division/partial_quotient_division/v/partial-quotient-method-of-division-2
http://en.wikipedia.org/wiki/Division_algorithm
http://en.wikipedia.org/wiki/Barrett_reduction
http://en.wikipedia.org/wiki/Euclidean_division
-}


quotRemNatural :: Natural -> Natural -> (Natural, Natural)
quotRemNatural !numer@(Natural !nn !narr) !denom@(Natural !dn !darr)
    | dn > nn = (zeroNatural, numer)
    | dn == nn && indexWordArray narr (nn - 1) < indexWordArray darr (nn - 1) = (zeroNatural, numer)
    | dn == nn && indexWordArray narr (nn - 1) == indexWordArray darr (nn - 1) =
                    if ltNatural numer denom
                        then (zeroNatural, numer)
                        else (oneNatural, minusNatural numer denom)
#if 0
    | otherwise = error ("New3/GHC/Integer/Type.hs: line " ++ show (__LINE__ :: Int))
#else
    | otherwise = divideOnceNatural numer denom

{-
      runStrictPrim $ do
        qlen <- return $! if indexWordArray darr (dn - 1) >= indexWordArray narr (nn - 1) then n - 1 else n
        qmarr <- newWordArray n
        rmarr <- newWordArray n
        rem <- loop (n - 1) qmarr 0
        qarr <- unsafeFreezeWordArray qmarr
        return $! (Natural qlen qarr, rem)

divideSimple :: Natural -> Natural -> (Natural, Natural)
divideSimple numer denom =
    let nd# = encodeDoubleNatural numer 0#
        dd# = encodeDoubleNatural denom 0#
        q = decodeDoubleNatural (nd# /## dd#)
    in (q, minusNatural numer (timesNatural q denom))

-}


#endif

divideOnceNatural :: Natural -> Natural -> (Natural, Natural)
divideOnceNatural numer denom =
    let !(q1, r1) = partialQuotient numer
    in case q1 of
        Natural 0 _ -> (q1, r1)
        _ ->
            let !(!q2, !r2) = divideOnceNatural r1 denom
            in (plusNatural q1 q2, r2)
  where
    {-# INLINE partialQuotient #-}
    partialQuotient :: Natural -> (Natural, Natural)
    partialQuotient num =
        let (m, s) = partialQuotientWord num denom
        in case m of
            0 -> (zeroNatural, num)
            _ ->
                let !qt = shiftLNatural (wordToNatural m) (64 * s)
                    !pr = timesNatural denom qt
                    !rm  = minusNatural num pr
                in (qt, rm)

    {-# INLINE partialQuotientWord #-}
    partialQuotientWord :: Natural -> Natural -> (Word, Int)
    partialQuotientWord !(Natural !nn !narr) !(Natural !dn !darr) =
        let !n0 = indexWordArray narr (nn - 1)
            !d0 = indexWordArray darr (dn - 1)
        in case (# compare dn nn, compare n0 d0 #) of
            (# GT, _ #) -> (0, 0)
            (# EQ, LT #) -> (0, 0)
            (# EQ, EQ #) -> (1, nn - dn)
            (# EQ, GT #) -> case quotRemWord n0 d0 of (# !q, _ #) -> (q, nn - dn)
            (# LT, LT #) -> case quotRemWord2 n0 (indexWordArray narr $ nn - 2) d0 of (# !q, _ #) -> (q, nn - dn - 1)
            (# LT, _ #) -> case quotRemWord n0 d0 of (# !q, _ #) -> (q, nn - dn)


eqNatural :: Natural -> Natural -> Bool
eqNatural !(Natural !n1 !arr1) !(Natural !n2 !arr2)
    | n1 /= n2 = False
    | otherwise =
        let eqArray !idx
                | idx < 0 = True
                | indexWordArray arr1 idx /= indexWordArray arr2 idx = False
                | otherwise = eqArray (idx - 1)
        in eqArray (n1 - 1)

compareNatural :: Natural -> Natural -> Ordering
compareNatural !(Natural !n1 !arr1) !(Natural !n2 !arr2)
    | n1 < n2 = LT
    | n1 > n2 = GT
    | otherwise =
        let cmpArray !idx
                | idx < 0 = EQ
                | otherwise =
                    case compare (indexWordArray arr1 idx) (indexWordArray arr2 idx) of
                        EQ -> cmpArray (idx - 1)
                        cmp -> cmp
        in cmpArray (n1 - 1)


ltNatural :: Natural -> Natural -> Bool
ltNatural !(Natural !n1 !arr1) !(Natural !n2 !arr2)
    | n1 < n2 = True
    | n1 > n2 = False
    | otherwise =
        let check 0 = indexWordArray arr1 0 < indexWordArray arr2 0
            check i =
                if indexWordArray arr1 i == indexWordArray arr2 i
                    then check (i - 1)
                    else indexWordArray arr1 i < indexWordArray arr2 i
        in check (n1 - 1)


gtNatural :: Natural -> Natural -> Bool
gtNatural !(Natural !n1 !arr1) !(Natural !n2 !arr2)
    | n1 > n2 = True
    | n1 < n2 = False
    | otherwise =
            let check 0 = indexWordArray arr1 0 > indexWordArray arr2 0
                check i =
                    if indexWordArray arr1 i == indexWordArray arr2 i
                        then check (i - 1)
                        else indexWordArray arr1 i > indexWordArray arr2 i
            in check (n1 - 1)


--------------------------------------------------------------------------------
-- Helpers (not part of the API).


{-# INLINE unboxWord #-}
unboxWord :: Word -> Word#
unboxWord !(W# !w) = w


{-# INLINE unboxInt #-}
unboxInt :: Int -> Int#
unboxInt !(I# !i) = i


{-# INLINE zerothWordOfNatural #-}
zerothWordOfNatural :: Natural -> Word
zerothWordOfNatural !(Natural _ arr) = indexWordArray arr 0

mkPair :: Word -> Word -> Natural
mkPair !sm !carry = runStrictPrim mkNatPair
  where
    mkNatPair :: StrictPrim s Natural
    mkNatPair = do
        marr <- newWordArray 2
        writeWordArray marr 0 sm
        writeWordArray marr 1 carry
        narr <- unsafeFreezeWordArray marr
        return $ Natural 2 narr

mkSingletonNat :: Word -> Natural
mkSingletonNat !x = runStrictPrim mkNat
  where
    mkNat :: StrictPrim s Natural
    mkNat = do
        marr <- newWordArray 1
        writeWordArray marr 0 x
        narr <- unsafeFreezeWordArray marr
        return $ Natural 1 narr


finalizeNatural :: Int -> WordArray -> StrictPrim s Natural
finalizeNatural 0 _ = return zeroNatural
finalizeNatural !nin !arr = do
    let !len = nonZeroLen nin arr
    x <- indexWordArrayM arr 0
    return $
        if len < 0 || (len == 1 && x == 0)
            then zeroNatural
            else Natural len arr

nonZeroLen :: Int -> WordArray -> Int
nonZeroLen !len !arr
    | len < 1 = 0
    | otherwise =
        let trim i
                | i < 0 = 0
                | indexWordArray arr i == 0 = trim (i - 1)
                | otherwise = i + 1
        in trim (len - 1)


zeroNatural, oneNatural :: Natural
zeroNatural = runStrictPrim $ do
        marr <- newWordArray 1
        writeWordArray marr 0 0
        narr <- unsafeFreezeWordArray marr
        return $! Natural 0 narr
oneNatural = wordToNatural 1

wordToNatural :: Word -> Natural
wordToNatural w = runStrictPrim $ do
        marr <- newWordArray 1
        writeWordArray marr 0 w
        narr <- unsafeFreezeWordArray marr
        return $! Natural 1 narr


arrayShow :: Int -> WordArray -> String
arrayShow !len !arr =
    let hexify w =
            let x = showHex w ""
            in replicate (16 - length x) '0' ++ x
        digits = dropWhile (== '0') . concatMap hexify . reverse $ unpackArray 0
    in if null digits then "0x0" else "0x" ++ digits
  where
    unpackArray i
        | i < len = do
                let xs = unpackArray (i + 1)
                    x = indexWordArray arr i
                x : xs
        | otherwise = []


hexShowW :: Word -> String
hexShowW w = "0x" ++ showHex w ""

signShow :: Sign -> String
signShow Pos = "Pos"
signShow Neg = "Neg"

absInt :: Int -> Int
absInt x = if x < 0 then -x else x

debugPrint :: Int -> String -> StrictPrim s ()
debugPrint line s = trace (show line ++ " : " ++ s) $ return ()


debugWriteWordArray :: Int -> MutableWordArray (StrictPrim s) -> Int -> Word -> StrictPrim s ()
# if 0
debugWriteWordArray line marr i x = do
    debugPrint line $ "writing " ++ hexShowW x ++ " at " ++ show i
    writeWordArray marr i x
#else
debugWriteWordArray _ marr i x = writeWordArray marr i x
#endif

traceNatural :: Int -> Natural -> Natural
traceNatural linenum nat@(Natural n arr) =
    if n <= 0
        then error $ "Bad natural (" ++ show linenum ++ ") " ++ show n ++ " " ++ arrayShow n arr
        else nat

errorLine :: Int -> String -> a
errorLine linenum s = error $ "Line " ++ show linenum ++ ": " ++ s

#endif
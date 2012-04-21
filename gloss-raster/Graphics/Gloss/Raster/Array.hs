
{-# LANGUAGE BangPatterns, MagicHash, PatternGuards, ScopedTypeVariables #-}

-- | Rendering of Repa arrays as raster images.
--
--  Gloss programs should be compiled with @-threaded@, otherwise the GHC runtime
--  will limit the frame-rate to around 20Hz.
--
--  The performance of programs using this interface is sensitive to how much
--  boxing and unboxing the GHC simplifier manages to eliminate. For the best
--  result add INLINE pragmas to all of your numeric functions and use the following
--  compile options.  
--
--  @-threaded -Odph -fno-liberate-case -funfolding-use-threshold1000 -funfolding-keeness-factor1000 -fllvm -optlo-O3@
--
--  See the examples the @raster@ directory of the @gloss-examples@ package 
--  for more details.
--
module Graphics.Gloss.Raster.Array
        ( -- * Color
          module Graphics.Gloss.Data.Color
        , rgb, rgb8, rgb8w

          -- * Display functions
        , Display       (..)
        , animateArray)
--        , playArray)
where
import Graphics.Gloss.Data.Color
import Graphics.Gloss.Data.Picture
import Graphics.Gloss.Data.Display
import Graphics.Gloss.Interface.Pure.Game
import Graphics.Gloss.Interface.IO.Animate
import Data.Word
import System.IO.Unsafe
import Unsafe.Coerce
import Debug.Trace
import Data.Bits
import Data.Array.Repa                          as R
import Data.Array.Repa.Repr.ForeignPtr          as R
import Prelude                                  as P

-- Color ----------------------------------------------------------------------
-- | Construct a color from red, green, blue components.
--  
--   Each component is clipped to the range [0..1]
rgb  :: Float -> Float -> Float -> Color
rgb r g b   = makeColor r g b 1.0
{-# INLINE rgb #-}


-- | Construct a color from red, green, blue components.
--
--   Each component is clipped to the range [0..255]
rgb8 :: Int -> Int -> Int -> Color
rgb8 r g b  = makeColor8 r g b 255
{-# INLINE rgb8 #-}


-- | Construct a color from red, green, blue components.
rgb8w :: Word8 -> Word8 -> Word8 -> Color
rgb8w r g b = makeColor8 (fromIntegral r) (fromIntegral g) (fromIntegral b) 255
{-# INLINE rgb8w #-}


-- Animate --------------------------------------------------------------------
-- | Animate a continuous 2D function.
animateArray
        :: Display                      
                -- ^ Display mode.
        -> (Int, Int)
                -- ^ Scale factor
        -> (Float -> Array D DIM2 Color)
                -- ^ A function to construct a delayed array for the given time.
                --   The function should return an array of the same extent each 
                --   time it is applied.
                --
                --   It is passed the time in seconds since the program started.
        -> IO ()
        
animateArray display scale makeArray
 = let  {-# INLINE frame #-}
        frame !time          = return $ makeFrame scale (makeArray time)
   in   animateFixedIO display black frame
{-# INLINE animateArray #-}
--  INLINE so the repa functions fuse with the users client functions.

{-
-- Play -----------------------------------------------------------------------
-- | Play a game with a continous 2D function.
playField 
        :: Display                      
                -- ^ Display mode.
        -> (Int, Int)   
                -- ^ Pixels per point.
        -> Int  -- ^ Number of simulation steps to take
                --   for each second of real time
        -> world 
                -- ^ The initial world.
        -> (world -> Point -> Color)    
                -- ^ Function to compute the color of the world at the given point.
        -> (Event -> world -> world)    
                -- ^ Function to handle input events.
        -> (Float -> world -> world)    
                -- ^ Function to step the world one iteration.
                --   It is passed the time in seconds since the program started.
        -> IO ()
playField !display (zoomX, zoomY) !stepRate !initWorld !makePixel !handleEvent !stepWorld
 = zoomX `seq` zoomY `seq`
   if zoomX < 1 || zoomY < 1
     then  error $ "Graphics.Gloss.Raster.Field: invalid pixel multiplication " 
                 P.++ show (zoomX, zoomY)
     else  let  (winSizeX, winSizeY) = sizeOfDisplay display
           in   winSizeX `seq` winSizeY `seq`
                play display black stepRate 
                   initWorld
                   (\world -> 
                      world `seq` 
                      makeFrame winSizeX winSizeY zoomX zoomY (makePixel world))
                   handleEvent
                   stepWorld
{-# INLINE playField #-}
-}

-- Frame ----------------------------------------------------------------------
{-# INLINE makeFrame #-}
makeFrame :: (Int, Int) -> Array D DIM2 Color -> Picture
makeFrame (scaleX, scaleY) !array
 = let  -- Size of the array
        _ :. sizeY :. sizeX 
                         = R.extent array

        {-# INLINE convColor #-} 
        convColor :: Color -> Word32
        convColor color
         = let  (r, g, b) = unpackColor color
                r'        = fromIntegral r
                g'        = fromIntegral g
                b'        = fromIntegral b
                a         = 255 

                !w        =  unsafeShiftL r' 24
                         .|. unsafeShiftL g' 16
                         .|. unsafeShiftL b' 8
                         .|. a
           in   w

   in unsafePerformIO $ do

        -- Define the image, and extract out just the RGB color components.
        -- We don't need the alpha because we're only drawing one image.
        traceEventIO "Gloss.Raster[makeFrame]: start frame evaluation."
        (arrRGB :: Array F DIM2 Word32)
                <- R.computeP $ R.map convColor array
        traceEventIO "Gloss.Raster[makeFrame]: done, returning picture."

        -- Wrap the ForeignPtr from the Array as a gloss picture.
        let picture     
                = Scale (fromIntegral scaleX) (fromIntegral scaleY)
                $ bitmapOfForeignPtr
                        sizeX sizeY     -- raw image size
                        (R.toForeignPtr $ unsafeCoerce arrRGB)   
                                        -- the image data.
                        False           -- don't cache this in texture memory.

        return picture


-- | Float to Word8 conversion because the one in the GHC libraries
--   doesn't have enout specialisations and goes via Integer.
{-# INLINE word8OfFloat #-}
word8OfFloat :: Float -> Word8
word8OfFloat f
        = fromIntegral (truncate f :: Int) 


{-# INLINE unpackColor #-}
unpackColor :: Color -> (Word8, Word8, Word8)
unpackColor c
        | (r, g, b, _) <- rgbaOfColor c
        = ( word8OfFloat (r * 255)
          , word8OfFloat (g * 255)
          , word8OfFloat (b * 255))

{-# INLINE sizeOfDisplay #-}
sizeOfDisplay :: Display -> (Int, Int)
sizeOfDisplay display
 = case display of
        InWindow _ s _  -> s
        FullScreen s    -> s


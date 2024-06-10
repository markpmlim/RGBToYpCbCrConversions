### Convert an RGBA formatted image to a CVPixelBuffer object

<br />
<br />

This project consists of 2 simple demos to illustrate how to convert an image formatted in RGBA color space to one in Y'CbCr color space where Y' means Y prime (or Yp).  

The first demo creates a 3-plane CVPixelBuffer object to store the Yp, Cb and Cr components.

The second demo creates a biplanar CVPixelBuffer object to store the Yp and CbCr components.

It is recommended to convert the RGBA image to an ARGB vImage_Buffer object before the conversion from RGBA color space to Y'CbCr color space.

<br />
<br />

To ease the problem of copying the Yp, Cb, Cr (or Yp, CbCb) components to/from the planes of the CVPixelBuffer, Apple has provided the following functions:

```swift

    vImageBuffer_InitForCopyToCVPixelBuffer and vImageBuffer_InitForCopyFromCVPixelBuffer

```    
and

```swift

    vImageBuffer_CopyToCVPixelBuffer and vImageBuffer_InitWithCVPixelBuffer

``` 

<br />
<br />

Both demos call the function **vImageBuffer_InitForCopyToCVPixelBuffer** to initialise the planes of the CVPixelBuffer object properly.  We will copy the pixels of the vImage_Buffer objects to the planes of the CVPixelBuffer object with the following function:

```swift

    copyPixels(from sourceBuffers: [vImage_Buffer],
               to cvPixelBuffer: CVPixelBuffer)

``` 

<br />
<br />

As commented in the code of this function, we can copy the pixels of the entire 2D region with just one line of code or we can copy the pixels of the 2D regions row by row.

<br />
<br />

To reverse the conversion from YpCbCr space to RGBA space, we can adopt the following approaches:

a) create 2 or more vImage_Buffer objects directly from the CVPixelBuffer object and then apply one of the functions:

```swift

    vImageConvert_420Yp8_Cb8_Cr8ToARGB8888 or vImageConvert_420Yp8_CbCr8ToARGB8888
    
``` 

b) instantiate 2 or 3 instances of MTLTextures and send these to a kernel function to convert into an RGBA formatted MTLTexture. A pair of vertex-fragment functions is required to display the constituted image on the screen. This approach allows the 3 separate luminance (Y), Cb chrominance and Cr chrominance channels or 2 separate luminance (Y) and two-channel chrominance (CbCr) channels to be saved.

<br />
<br />

**Development Platform:**

XCode 11.6, macOS 10.15

<br />
<br />

**References:**

a) Understanding YpCbCr Image Formats 

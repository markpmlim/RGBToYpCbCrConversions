//
//  ViewController.swift
//  RGBToYp_Cb_CrCVPixelBuffer
//
//  Created by mark lim pak mun on 12/06/2024.
//  Copyright © 2024 Incremental Innovations. All rights reserved.
//

import AppKit
import Accelerate.vImage

class ViewController: NSViewController
{

    @IBOutlet var imageView: NSImageView!

    var cgImageFormat = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 8*4,
        colorSpace: nil,            // default to sRGB
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),    // ARGB
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)

    // unused
    var grayScaleImageFormat = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        colorSpace: Unmanaged.passRetained(CGColorSpace(name: CGColorSpace.linearGray)!),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)

    // The contents of this object include a 3x3 matrix and clamping info.
    var infoYpCbCrToARGB = vImage_YpCbCrToARGB()

    var destinationBuffer = vImage_Buffer()

    var cvPixelBuffer: CVPixelBuffer!

    override func viewDidLoad()
    {
        super.viewDidLoad()
        guard let cgImage = loadImage()
        else {
            return
        }
        cvPixelBuffer = imageToYUVCVPixelBuffer(cgImage: cgImage)
        // Convert the CVPixelBuffer object to ARGB vImage_Buffer.
        convertYp_Cb_CrToARGB(cvPixelBuffer!)
        display()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    deinit {
        destinationBuffer.free()
    }

    /*
     Instantiate an instance of CGImage, followed by an instance of NSImage
     and display the latter within the window.
     */
    func display()
    {
        var error = vImage_Error(kvImageNoError)
        let cgImage = vImageCreateCGImageFromBuffer(
            &destinationBuffer,
            &cgImageFormat,
            nil,
            nil,
            vImage_Flags(kvImageNoFlags),
            &error)

        if let cgImage = cgImage,
            error == kvImageNoError {
            DispatchQueue.main.async {
                // The bitmapInfo of CGImage is non-premultiplied RGBA
                self.imageView.image = NSImage(cgImage: cgImage.takeUnretainedValue(),
                                               size: NSZeroSize)
            }
        }
    }

    /*
     Instantiate a CGImage object by loading a graphic image from
     the Resources folder of this demo.
     */
    func loadImage() -> CGImage?
    {
        guard let url = Bundle.main.urlForImageResource(NSImage.Name(rawValue: "Hibiscus.png"))
        else {
            return nil
        }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            return nil
        }

        let options = [
            kCGImageSourceShouldCache as String : true,
            kCGImageSourceShouldAllowFloat as String : false
            ] as CFDictionary
        
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, options)
        else {
            return nil
        }

        // The bitmapInfo of `image` is non-premultiplied RGBA
        return image
    }

    func configureYpCbCrToARGBInfo() -> vImage_Error
    {
        // video range 8-bit, clamped to video range
        // The bias will be the prebias for YUV -> RGB and postbias for RGB -> YUV
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 16,
            CbCr_bias: 128,
            YpRangeMax: 235,
            CbCrRangeMax: 240,
            YpMax: 235,
            YpMin: 16,
            CbCrMax: 240,
            CbCrMin: 16)

        // Fill the vImage_YpCbCrToARGB struct with the correct values
        let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_601_4!,
            &pixelRange,
            &infoYpCbCrToARGB,
            kvImage420Yp8_Cb8_Cr8,      // OSType: y420 / f420
            kvImageARGB8888,            // Any 8-bit, 4-channel interleaved buffer
            vImage_Flags(kvImageNoFlags))

        return error
    }

    // Convert the RGBA image into a CVPixelBuffer object with 3 planes.
    func imageToYUVCVPixelBuffer(cgImage: CGImage) -> CVPixelBuffer?
    {
        let unmanagedCVImageFormat = vImageCVImageFormat_Create(
            kCVPixelFormatType_420YpCbCr8Planar,
            kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4,
            kCVImageBufferChromaLocation_Center,
            CGColorSpaceCreateDeviceRGB(),
            0)

        let cvImageFormat = unmanagedCVImageFormat!.takeRetainedValue()

        defer {
            unmanagedConverter?.release()
        }

        var error = vImage_Error(kvImageNoError)

        let backGroundColor: [CGFloat] = [0.0, 0.0, 0.0, 0.0]

        let unmanagedConverter = vImageConverter_CreateForCGToCVImageFormat(
            &cgImageFormat,
            cvImageFormat,
            backGroundColor,
            vImage_Flags(kvImagePrintDiagnosticsToConsole),
            &error)

        // First, create several vImage_Buffer objects that will correspond
        // to the planes of the CVPixelBuffer object.
        let cgToCvConverter = unmanagedConverter!.takeUnretainedValue()
        //let sourceBufferCount = Int(vImageConverter_GetNumberOfSourceBuffers(cgToCvConverter))
        // A vImage_Buffer object each for Y, Cb and Cr channels
        let destinationBufferCount = Int(vImageConverter_GetNumberOfDestinationBuffers(cgToCvConverter))
        // Check the format of vImage_Buffer is ARGB
        var argbSourceBuffer = try! vImage_Buffer(cgImage: cgImage,
                                                  format: cgImageFormat)

        // Check the pixels are in ARGB format
        let bufferPtr = argbSourceBuffer.data.assumingMemoryBound(to: UInt8.self)
        for i in 0 ..< 2*cgImageFormat.componentCount {
            print(String(format: "0x%02X", bufferPtr[i]), terminator: " ")
        }
        print()

        defer {
            argbSourceBuffer.free()
        }

        // Initialise 3 "empty" vImage_Buffer objects.
        // Note: their `data` properties are still NIL.
        var ypCbCr8PlanarBuffers = (0 ..< destinationBufferCount).map { _ in
            return vImage_Buffer()
        }

        var cvPixelBuffer: CVPixelBuffer?
        let pixelBufferAttributes = [
            kCVPixelBufferIOSurfacePropertiesKey as String : [String: Any]()
            ] as CFDictionary

        // Create a triplanar CVPixelBuffer object.
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            cgImage.width, cgImage.height,
            kCVPixelFormatType_420YpCbCr8Planar,
            pixelBufferAttributes,
            &cvPixelBuffer)

        guard result == kCVReturnSuccess
        else {
            return nil
        }

        // We must lock the CVPixelBuffer object or an error of  -21781 (kvImageInvalidImageObject)
        // will be returned and the array `ypCbCr8PlanarBuffers` will NOT be initialised properly.
        // Memory will be allocated to the `data` property of each of the 3 vImage_Buffer objects.
        CVPixelBufferLockBaseAddress(cvPixelBuffer!, .readOnly)
        error = vImageBuffer_InitForCopyToCVPixelBuffer(
            &ypCbCr8PlanarBuffers,
            cgToCvConverter,
            cvPixelBuffer!,
            vImage_Flags(kvImageNoAllocate))

        // Do we have to release the memory allocated to the ypCbCr8PlanarBuffers? - No
        error = vImageConvert_AnyToAny(
            cgToCvConverter,
            &argbSourceBuffer,      // srcs
            ypCbCr8PlanarBuffers,   // dests
            nil,
            vImage_Flags(kvImageNoFlags))

        // On return from the above call, the 2D `data` regions of the 3 vImage_Buffer objects
        // and 3 planes of the CVPixelBuffer will be populated with pixels.
        CVPixelBufferUnlockBaseAddress(cvPixelBuffer!, .readOnly)
        return cvPixelBuffer
    }

    /*
     Convert the CVPixelBuffer to an ARGB-based vImageBuffer.
     Initialise the luminance, blue-difference chrominance and red-difference chrominance
     vImage buffers directly from the three planes of the pixel buffer object.
    */
    func convertYp_Cb_CrToARGB(_ pixelBuffer: CVPixelBuffer)
    {
        assert(CVPixelBufferGetPlaneCount(pixelBuffer) == 3,
               "Pixel Buffer should have 3 planes")

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        var sourceLumaBuffer = vImage_Buffer(
            data: lumaBaseAddress,
            height: vImagePixelCount(lumaHeight),
            width: vImagePixelCount(lumaWidth),
            rowBytes: lumaRowBytes)

        let chromaCbBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        let chromaCbWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaCbHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let chromaCbRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        var sourceChromaCbBuffer = vImage_Buffer(
            data: chromaCbBaseAddress,
            height: vImagePixelCount(chromaCbHeight),
            width: vImagePixelCount(chromaCbWidth),
            rowBytes: chromaCbRowBytes)

        let chromaCrBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 2)
        let chromaCrWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 2)
        let chromaCrHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 2)
        let chromaCrRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 2)
        
        var sourceChromaCrBuffer = vImage_Buffer(
            data: chromaCrBaseAddress,
            height: vImagePixelCount(chromaCrHeight),
            width: vImagePixelCount(chromaCrWidth),
            rowBytes: chromaCrRowBytes)

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            // The memory pointers of sourceLumaBuffer, sourceChromaCbBuffer and
            // sourceChromaCrBuffer are owned by the system.
        }

        // Initialise the Destination Buffer; its size should match the luminance plane of the pixel buffer
        var error = kvImageNoError
        if destinationBuffer.data == nil {
            error = vImageBuffer_Init(
                &destinationBuffer,
                sourceLumaBuffer.height,
                sourceLumaBuffer.width,
                cgImageFormat.bitsPerPixel,
                vImage_Flags(kvImageNoFlags))

            guard error == kvImageNoError
            else {
                return
            }
        }

        // Convert Yp, Cb and Cr vImage buffers to a 4-channel ARGB buffer
        configureYpCbCrToARGBInfo()
        error = vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
            &sourceLumaBuffer,          // srcYp vImage_Buffer
            &sourceChromaCbBuffer,      // srcCb vImage_Buffer
            &sourceChromaCrBuffer,      // srcCr vImage_Buffer
            &destinationBuffer,         // colour channel order should be ARGB
            &infoYpCbCrToARGB,          // Pointer to a vImage_YpCbCrToARGB struct
            nil,                        // permuteMap: no change in colour order (ARGB)
            255,                        // alpha value
            vImage_Flags(kvImagePrintDiagnosticsToConsole))

        // Check the pixels in `destinationBuffer` are in ARGB format.
        let bufferPtr = destinationBuffer.data.assumingMemoryBound(to: UInt8.self)
        for i in 0 ..< 2*cgImageFormat.componentCount {
            print(String(format: "0x%02X", bufferPtr[i]), terminator: " ")
        }
        print()

        guard error == kvImageNoError
        else {
            return
        }
    }
}


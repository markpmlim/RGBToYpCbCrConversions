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
        // Convert the CVPixelBuffer object to an ARGB vImage_Buffer.
        convertYp_CbCrToARGB(cvPixelBuffer!)
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
        let options = vImage.Options.highQualityResampling
        var cgImage: CGImage
        do {
            // Requires macOS 10.15 or later
            cgImage = try destinationBuffer.createCGImage(
                format: cgImageFormat,
                flags: options)
        }
        catch let error {
            print("Error: \(error) Can't instantiate CGImage from the destination buffer")
            return
        }

        DispatchQueue.main.async {
            // The bitmapInfo of CGImage is non-premultiplied RGBA
            self.imageView.image = NSImage(cgImage: cgImage,
                                           size: NSZeroSize)
        }
    }

    /*
     Instantiate a CGImage object by loading a graphic image from
     the Resources folder of this demo.
     */
    func loadImage() -> CGImage?
    {
        guard let url = Bundle.main.urlForImageResource(NSImage.Name("Hibiscus.png"))
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

        // Fill the vImage_YpCbCrToARGB struct with correct values
        let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_601_4!,
            &pixelRange,
            &infoYpCbCrToARGB,
            kvImage420Yp8_CbCr8,        // OSType: 420v / 420f
            kvImageARGB8888,            // Any 8-bit, 4-channel interleaved buffer
            vImage_Flags(kvImageNoFlags))

        return error
    }

    // Convert the RGBA image into a CVPixelBuffer object with 2 planes.
    func imageToYUVCVPixelBuffer(cgImage: CGImage) -> CVPixelBuffer?
    {
        var cvPixelBuffer: CVPixelBuffer?
        let pixelBufferAttributes = [
            kCVPixelBufferIOSurfacePropertiesKey as String : [String: Any]()
            ] as CFDictionary
        
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault,
            cgImage.width, cgImage.height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            pixelBufferAttributes,
            &cvPixelBuffer)
        
        guard result == kCVReturnSuccess
        else {
            print("Can't instantiate the CVPixelBuffer object", result)
            return nil
        }

        // There are 2 static functions in macOS 10.15 or later which can return
        // an instance of vImageCVImageFormat.
        let unmanagedCVImageFormat = vImageCVImageFormat_Create(
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
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

        // There are 3 type functions in macOS 10.15 or later which can return
        // an instance of vImageConverter
        let unmanagedConverter = vImageConverter_CreateForCGToCVImageFormat(
            &cgImageFormat,
            cvImageFormat,
            backGroundColor,
            vImage_Flags(kvImagePrintDiagnosticsToConsole),
            &error)

        // First, create two vImage_Buffer objects that correspond to the 2 planes
        // of the CVPixelBuffer object.
        let cgToCvConverter = unmanagedConverter!.takeUnretainedValue()
        //let sourceBufferCount = Int(vImageConverter_GetNumberOfSourceBuffers(cgToCvConverter))
        // A vImage_Buffer object each for Y and CbCr channels
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

        // Initialise 2 "empty" vImage_Buffer objects.
        // Note: their `data` properties are still NIL.
        var ypCbCr8PlanarBuffers = (0 ..< destinationBufferCount).map { _ in
            return vImage_Buffer()
        }

        // We must lock the CVPixelBuffer object or an error of  -21781 (kvImageInvalidImageObject)
        // will be returned and the array `ypCbCr8PlanarBuffers` will NOT be initialised properly.
        CVPixelBufferLockBaseAddress(cvPixelBuffer!, .readOnly)
        // The call below will allocate memory to the 2D `data` regions of the 2 vImage_Buffer objects.
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
        // On return from the above call, the 2D `data` regions will be populated with pixels.

        // Copy pixels from the vImage_Buffers objects to the corresponding CVPixelBuffer planes.
        copyPixels(from: ypCbCr8PlanarBuffers,
                   to: cvPixelBuffer!)
        CVPixelBufferUnlockBaseAddress(cvPixelBuffer!, .readOnly)
        return cvPixelBuffer
    }

    func copyPixels(from sourceBuffers: [vImage_Buffer],
                    to cvPixelBuffer: CVPixelBuffer)
    {
        assert(CVPixelBufferGetPlaneCount(cvPixelBuffer) == 2,
               "2 planes expected")
        CVPixelBufferLockBaseAddress(cvPixelBuffer,
                                     CVPixelBufferLockFlags(rawValue: 0))
        // For debugging:
        // vImage_Buffer(data: Optional(0x0000000108800020), height: 600, width: 800, rowBytes: 800)
        // vImage_Buffer(data: Optional(0x0000000108875320), height: 600, width: 800, rowBytes: 800)
        // <Plane 0 width=800 height=600 bytesPerRow=800>   // 1 byte/pixel
        // <Plane 1 width=400 height=300 bytesPerRow=800>   // 2 bytes/pixel

        // Optimised copy. We can copy an entire plane instead of row by row
        for planeIndex in 0 ..< sourceBuffers.count {
            let destBaseAddress = CVPixelBufferGetBaseAddressOfPlane(cvPixelBuffer, planeIndex)
            memcpy(destBaseAddress,
                   sourceBuffers[planeIndex].data,
                   sourceBuffers[planeIndex].rowBytes*Int(sourceBuffers[planeIndex].height))
        }

        CVPixelBufferUnlockBaseAddress(cvPixelBuffer, .readOnly)
    }

    /*
     Convert the CVPixelBuffer to an ARGB-based vImageBuffer.
     Initialize the source luminance and chrominance vImage buffers directly from the
     two planes of the pixel buffer object.
    */
    func convertYp_CbCrToARGB(_ pixelBuffer: CVPixelBuffer)
    {
        assert(CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
               "Pixel Buffer should have 2 planes")

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

        let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        var sourceChromaBuffer = vImage_Buffer(
            data: chromaBaseAddress,
            height: vImagePixelCount(chromaHeight),
            width: vImagePixelCount(chromaWidth),
            rowBytes: chromaRowBytes)

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            // The memory pointers of sourceLumaBuffer and sourceChromaBuffer are owned by the system.
        }

        // Initialise the Destination Buffer; its size should match the luminance plane of the pixel buffer
        var error = kvImageNoError
        if destinationBuffer.data == nil {
            error = vImageBuffer_Init(&destinationBuffer,
                                      sourceLumaBuffer.height,
                                      sourceLumaBuffer.width,
                                      cgImageFormat.bitsPerPixel,
                                      vImage_Flags(kvImageNoFlags))

            guard error == kvImageNoError
            else {
                return
            }
        }

        // Convert Yp and CbCr vImage buffers to a 4-channel ARGB buffer
        configureYpCbCrToARGBInfo()
        error = vImageConvert_420Yp8_CbCr8ToARGB8888(
            &sourceLumaBuffer,      // srcYp vImage_Buffer
            &sourceChromaBuffer,    // srcCbCr vImage_Buffer
            &destinationBuffer,     // colour channel order should be ARGB
            &infoYpCbCrToARGB,
            nil,                    // permuteMap: no change in colour order (ARGB)
            255,                    // alpha value
            vImage_Flags(kvImagePrintDiagnosticsToConsole))

        // Check the pixels are in ARGB format
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


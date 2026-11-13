// Remove an image background on-device with Apple Vision (macOS 14+).
// Usage: remove_bg_vision <input-image> <output.png>
// Exit codes: 0 success, 2 bad arguments / unreadable input, 3 no subject found, 4 processing failed.
import AppKit
import CoreImage
import ImageIO
import Vision
import UniformTypeIdentifiers

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: remove_bg_vision <input-image> <output.png>", code: 2)
}
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

// Apply EXIF orientation so the mask and the output match what the user sees.
guard let foreground = CIImage(contentsOf: inputURL, options: [.applyOrientationProperty: true]) else {
    fail("Could not decode the input image", code: 2)
}

do {
    let handler = VNImageRequestHandler(ciImage: foreground, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first,
          !observation.allInstances.isEmpty else {
        fail("No foreground subject was detected", code: 3)
    }
    print("Detected foreground instances: \(observation.allInstances)")
    let foregroundMask = try observation.generateScaledMaskForImage(
        forInstances: observation.allInstances,
        from: handler
    )

    let extent = foreground.extent
    let maskImage = CIImage(cvPixelBuffer: foregroundMask)
    let mask = maskImage.transformed(by: CGAffineTransform(
        scaleX: extent.width / maskImage.extent.width,
        y: extent.height / maskImage.extent.height
    ))
    let transparent = CIImage(color: CIColor.clear).cropped(to: extent)
    let result = foreground.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: transparent,
        kCIInputMaskImageKey: mask
    ])

    let context = CIContext(options: [.useSoftwareRenderer: false])
    try context.writePNGRepresentation(
        of: result,
        to: outputURL,
        format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        options: [:]
    )
    print("Saved \(Int(extent.width)) × \(Int(extent.height)) transparent PNG to \(outputURL.path)")
} catch {
    fail("Vision background removal failed: \(error.localizedDescription)", code: 4)
}

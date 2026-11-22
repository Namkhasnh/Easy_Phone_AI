import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let inDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let ctx = CIContext()
let files = try FileManager.default.contentsOfDirectory(atPath: inDir.path).filter { $0.hasSuffix(".png") }.sorted()
for name in files {
    let url = inDir.appendingPathComponent(name)
    let handler = VNImageRequestHandler(url: url)
    let req = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([req])
    guard let obs = req.results?.first else { print("no subject", name); continue }
    let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
    let ci = CIImage(cvPixelBuffer: buf)
    let out = outDir.appendingPathComponent(name)
    try ctx.writePNGRepresentation(of: ci, to: out, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}
print("done", files.count)

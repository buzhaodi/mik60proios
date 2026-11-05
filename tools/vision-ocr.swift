// macOS Vision-framework OCR for boot-log / panic-screen photographs.
//
// The board has no kernel-side serial console, so every hardware round is
// judged from screen photos and video frames; this reads them locally with
// no model API (the flash-model image subagent may be unavailable or billed).
// Run:  swift tools/vision-ocr.swift <image>          (single image)
//       swift tools/vision-ocr-batch.swift <dir>      (a directory of frames)
// Upscaling first helps small text:  sips --resampleWidth 3*W in.jpg --out big.jpg
//
// Lines are returned in reading order with y/x coordinates (Vision's
// bounding box has its origin at the BOTTOM-left, so y is flipped).
import Foundation
import Vision
import AppKit

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: vision-ocr <image_path>\n".data(using: .utf8)!)
    exit(1)
}
let url = URL(fileURLWithPath: args[1])

guard let img = NSImage(contentsOf: url),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot load image\n".data(using: .utf8)!)
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
request.usesLanguageCorrection = false  // hex/technical text: correction mangles it

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([request])

struct Line {
    let y: CGFloat
    let x: CGFloat
    let text: String
}

var lines: [Line] = []
for obs in request.results ?? [] {
    guard let cand = obs.topCandidates(1).first else { continue }
    let b = obs.boundingBox  // origin bottom-left, normalized
    lines.append(Line(y: b.origin.y, x: b.minX, text: cand.string))
}

// Vision y is from bottom; sort top-to-bottom, left-to-right
lines.sort { abs($0.y - $1.y) > 0.01 ? $0.y > $1.y : $0.x < $1.x }

if lines.isEmpty {
    print("(no text recognized)")
} else {
    for l in lines {
        print(String(format: "[y=%.2f x=%.2f] %@", 1 - l.y, l.x, l.text))
    }
}

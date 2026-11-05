// Batch companion of tools/vision-ocr.swift: OCR every .png/.jpg in a directory
// (video frames extracted with e.g.
//    ffmpeg -i boot.mp4 -vf "fps=2,scale=2560:1440" frames/f_%03d.png )
// in reading order, one block per image. Used to reconstruct the cleared -v
// scroll from boot videos when the panic screen has already wiped the console.
// Run:  swift tools/vision-ocr-batch.swift <dir-or-file> [more paths...]
import Foundation
import Vision
import AppKit

func err(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count > 1 else { err("usage: vision-ocr-batch <image|dir> [more paths...]") }

func ocrImage(_ path: String) -> String {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return "  (cannot load image)"
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try? handler.perform([request])

    struct L { let y: CGFloat; let x: CGFloat; let t: String }
    var lines: [L] = []
    for obs in request.results ?? [] {
        guard let c = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox  // origin bottom-left, normalized
        lines.append(L(y: b.origin.y, x: b.minX, t: c.string))
    }
    lines.sort { abs($0.y - $1.y) > 0.008 ? $0.y > $1.y : $0.x < $1.x }
    return lines.isEmpty ? "  (no text recognized)" : lines.map { $0.t }.joined(separator: "\n")
}

for arg in args[1...] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: arg, isDirectory: &isDir) else { err("no such path: \(arg)") }
    var files: [String] = []
    if isDir.boolValue {
        files = (try? fm.contentsOfDirectory(atPath: arg))?
            .filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }
            .sorted()
            .map { arg + "/" + $0 } ?? []
    } else {
        files = [arg]
    }
    for f in files {
        print("=== \((f as NSString).lastPathComponent) ===")
        print(ocrImage(f))
    }
}

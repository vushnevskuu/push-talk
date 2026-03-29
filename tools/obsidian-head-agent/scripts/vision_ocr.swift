#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

struct Args {
    var imagePath: String?
    var languages: [String] = []
}

func parseArgs() -> Args {
    var result = Args()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iterator.next() {
        if arg == "--lang", let value = iterator.next() {
            result.languages.append(value)
            continue
        }
        if result.imagePath == nil {
            result.imagePath = arg
        }
    }
    return result
}

func orderedStrings(from observations: [VNRecognizedTextObservation]) -> [String] {
    return observations
        .sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        .compactMap { $0.topCandidates(1).first?.string }
}

let args = parseArgs()
guard let imagePath = args.imagePath else {
    fputs("usage: vision_ocr.swift <image-path> [--lang ru-RU] [--lang en-US]\n", stderr)
    exit(1)
}

let imageURL = URL(fileURLWithPath: imagePath)
guard let image = NSImage(contentsOf: imageURL) else {
    fputs("Failed to load image.\n", stderr)
    exit(2)
}

var rect = NSRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
    fputs("Failed to create CGImage.\n", stderr)
    exit(3)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.minimumTextHeight = 0.01
request.recognitionLanguages = args.languages.isEmpty ? ["ru-RU", "en-US"] : args.languages

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
    let observations = request.results ?? []
    let strings = orderedStrings(from: observations)
    print(strings.joined(separator: "\n"))
} catch {
    fputs("Vision OCR failed: \(error)\n", stderr)
    exit(4)
}

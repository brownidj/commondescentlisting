#!/bin/zsh
# Render UTF-8 transcript text using macOS CoreText. No extra PDF dependency.
set -euo pipefail
(( $# == 2 )) || { print -u2 'Usage: export_transcript_pdf.zsh INPUT.txt OUTPUT.pdf'; exit 2; }
/usr/bin/swift - "$1" "$2" <<'SWIFT'
import Foundation
import AppKit
import CoreText
import CoreGraphics

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let text = try String(contentsOf: source, encoding: .utf8)
guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw NSError(domain: "TranscriptPDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcript is empty."])
}
let style = NSMutableParagraphStyle()
style.lineSpacing = 0
style.lineHeightMultiple = 1
style.paragraphSpacing = 6
let attributed = NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black,
    .paragraphStyle: style
])
let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
var page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
guard let consumer = CGDataConsumer(url: destination as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
    throw NSError(domain: "TranscriptPDF", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create PDF."])
}
let path = CGPath(rect: page.insetBy(dx: 48, dy: 48), transform: nil)
var offset = 0
while offset < attributed.length {
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
    let range = CTFrameGetVisibleStringRange(frame)
    guard range.length > 0 else {
        throw NSError(domain: "TranscriptPDF", code: 3, userInfo: [NSLocalizedDescriptionKey: "PDF pagination made no progress."])
    }
    context.beginPDFPage(nil)
    context.textMatrix = .identity
    CTFrameDraw(frame, context)
    context.endPDFPage()
    offset += range.length
}
context.closePDF()
SWIFT

#!/bin/zsh
# Manual offline PDF regression. Uses only macOS Swift/CoreText/PDFKit.
set -euo pipefail
pdf_project="${0:A:h:h:h}"
pdf_temp="$(mktemp -d)"
trap 'rm -rf -- "$pdf_temp"' EXIT
python3 - "$pdf_temp/input.txt" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(('Karoo–Ferrar, São Paulo, Müller and bivalves.\n\n'*300)+'Final transcript words.\n',encoding='utf-8')
PY
/bin/zsh "${pdf_project}/scripts/export_transcript_pdf.zsh" "${pdf_temp}/input.txt" "${pdf_temp}/transcript.pdf"
/usr/bin/swift - "$pdf_temp/input.txt" "$pdf_temp/transcript.pdf" <<'SWIFT'
import Foundation
import PDFKit
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[2])),
      let rendered = document.string else { fatalError("PDF could not be read") }
func words(_ text: String) -> [String] {
    text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
}
precondition(document.pageCount > 1, "Pagination not exercised")
precondition(words(rendered) == words(source), "Transcript text differs, is missing, or includes extra labels")
print("PDF text, Unicode and pagination checks passed; visual inspection remains manual.")
SWIFT

#!/bin/zsh
# Offline paragraph grouping checks. Does not create a PDF or launch the app.
set -euo pipefail
pdf_project="${0:A:h:h:h}"
python3 - "$pdf_project" <<'PY'
from pathlib import Path
import sys, unittest
sys.path.insert(0,str(Path(sys.argv[1])/'scripts/lib'))
from transcript_pdf_text import transcript_pdf_text

class ParagraphTests(unittest.TestCase):
    def test_fragments_join_until_sentence_boundary(self):
        passages=['The Karoo record', 'contains fossils.', 'Another thought follows.']
        self.assertEqual(transcript_pdf_text(passages,target_words=5),
                         'The Karoo record contains fossils.\nAnother thought follows.\n')

    def test_explicit_paragraphs_are_retained(self):
        self.assertEqual(transcript_pdf_text(['First thought.\n\nSecond thought', 'continues here.']),
                         'First thought.\nSecond thought continues here.\n')

    def test_unpunctuated_fragments_have_bounded_groups(self):
        passages=['one two', 'three four', 'five six']
        self.assertEqual(transcript_pdf_text(passages,maximum_words=4),
                         'one two three four\nfive six\n')

    def test_unicode_words_and_order_are_unchanged(self):
        passages=['Karoo–Ferrar, São Paulo,', '“Müller’s bivalves.”', 'An additional observation.']
        result=transcript_pdf_text(passages,target_words=4)
        self.assertEqual(result.split(),' '.join(passages).split())
        self.assertNotIn('\n\n',result)
        self.assertEqual(len(result.splitlines()),2)

    def test_empty_input(self):
        self.assertEqual(transcript_pdf_text([]),'')

unittest.main(argv=[sys.argv[0]])
PY

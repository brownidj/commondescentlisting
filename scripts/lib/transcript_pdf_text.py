"""Paragraph layout for text-only PDF exports; never rewrites spoken words."""
import re


def transcript_pdf_text(passages, target_words=80, maximum_words=180):
    """Join timing fragments; prefer sentence ends and retain explicit paragraphs.

    Transcripts have no reliable topic/speaker boundaries. The size limit keeps
    unpunctuated recognition output readable without inventing speaker changes.
    """
    paragraphs, pending = [], []
    word_count = 0

    def flush():
        nonlocal word_count
        if pending:
            paragraphs.append(' '.join(pending))
            pending.clear()
            word_count = 0

    for passage in passages:
        # Blank lines inside a saved passage are deliberate paragraph boundaries.
        pieces = re.split(r'\n[ \t]*\n+', passage.replace('\r\n', '\n').replace('\r', '\n'))
        for index, piece in enumerate(pieces):
            if index:
                flush()
            text = ' '.join(piece.split())
            if not text:
                continue
            pending.append(text)
            word_count += len(text.split())
            sentence_end = re.search(r'''[.!?]["'”’»\)\]]*$''', text) is not None
            if (word_count >= target_words and sentence_end) or word_count >= maximum_words:
                flush()
    flush()
    return '\n'.join(paragraphs) + ('\n' if paragraphs else '')

#!/bin/zsh
# Offline regression: no acoustic model, media processing, download or publication.
set -euo pipefail
alignment_test_project="${0:A:h:h:h}"
export NLTK_DATA="${alignment_test_project}/work/whisperx-trial/nltk_data"
"${EPISODE_PYTHON:-${alignment_test_project}/work/whisperx-trial/venv/bin/python}" - "$alignment_test_project" <<'PY'
import ast,json,sys,unittest
from pathlib import Path
project=Path(sys.argv[1])
source=(project/'scripts/episode_pipeline/align_transcript.zsh').read_text().split("<<'PY'",1)[1].split('\n',1)[1].rsplit('\nPY',1)[0]
nodes=[node for node in ast.parse(source).body if isinstance(node,(ast.ClassDef,ast.FunctionDef)) and node.name in ['AlignmentWindowTokenizer','aligned_words_match']]
namespace={};exec(compile(ast.Module(body=nodes,type_ignores=[]),'word-mapping-functions','exec'),namespace)

class MappingTests(unittest.TestCase):
    def test_possessive_citation_does_not_split_a_word(self):
        import nltk
        text="Today, we're going with so-and-so et al.'s 2012 hypothesis. Another sentence."
        original=list(nltk.data.load('tokenizers/punkt_tab/english.pickle').span_tokenize(text))
        self.assertGreater(len(original),1)
        tokenizer=namespace['AlignmentWindowTokenizer']()
        spans=tokenizer.span_tokenize(text)
        self.assertEqual(spans,[(0,len(text))])
        # Mirror WhisperX's inclusive-end character selection/word reconstruction.
        words=[{'word':word} for a,b in spans for word in text[a:b+1].split()]
        self.assertTrue(namespace['aligned_words_match'](text,words))
        self.assertEqual(tokenizer.span_tokenize(''),[])

    def test_missing_reordered_or_split_words_still_fail(self):
        matches=namespace['aligned_words_match']
        self.assertFalse(matches("et al.'s study",[{'word':'et'},{'word':'al.'},{'word':"'s"},{'word':'study'}]))
        self.assertFalse(matches('first second',[{'word':'second'},{'word':'first'}]))
        self.assertFalse(matches('first second',[{'word':'first'}]))
        self.assertTrue(matches('two words',[{'word':'two'},{'word':'words','start':1.0,'end':1.2}]))

unittest.main(argv=['alignment-word-mapping'],verbosity=2)
PY

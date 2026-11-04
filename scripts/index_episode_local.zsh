#!/bin/zsh
# Offline local index; only explicit exports contribute shared vocabulary.
set -euo pipefail
local_project="${0:A:h:h}"
local_python="${LOCAL_INDEX_PYTHON:-${local_project}/work/local-index-benchmark/venv/bin/python}"
[[ -x "$local_python" ]] || { print -u2 'Local indexing environment missing: work/local-index-benchmark/venv'; exit 2; }
export HF_HOME="${LOCAL_INDEX_HF_HOME:-${local_project}/work/local-index-benchmark/model-cache}"
export HF_HUB_OFFLINE=1
export TOKENIZERS_PARALLELISM=false
exec "$local_python" -u - "$local_project" "$@" <<'PY_INDEX'
from pathlib import Path
import argparse, collections, hashlib, importlib.metadata, json, os, re, sys, time

sys.path.insert(0, str(Path(sys.argv[1])/'scripts/indexing/lib'))
from index_policy import recover_publications, load_blacklist, apply_blacklist

VERSION = 'local-index-3'
MODEL = 'urchade/gliner_small-v2.1'
KINDS = ['fossil', 'place', 'paper', 'article', 'author']
CUES = re.compile(r'\b(paper|study|research|article)\b', re.I)
PUBLICATION_CONTEXT = re.compile(r'\b(published|publication|journal|authored|written by|titled|entitled|doi)\b', re.I)
BLOCKED = {'i','we','you','you guys','he','she','they','it','will','david','facebook','twitter','youtube','wordpress','listenerville'}
TIME_TERMS = {'mesozoic','paleozoic','cenozoic','jurassic','triassic','cretaceous','permian','cambrian','ordovician','silurian','devonian','carboniferous','precambrian'}

def sha(value): return hashlib.sha256(value).hexdigest()
def load(path): return json.loads(path.read_text())
def canon(value): return re.sub(r'\s+', ' ', value.casefold()).strip()
def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix(path.suffix + '.pending')
    pending.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    pending.replace(path)

def reviewed_entries(document):
    if document.get('schema_version') != 1: raise ValueError('Invalid vocabulary schema')
    result = []
    for entry in document['entries']:
        # Fail closed for accidental raw registry/suggestion imports.
        if entry.get('review') != 'confirmed' or entry.get('deleted', False): continue
        if entry.get('kind') not in KINDS or not isinstance(entry.get('name'), str):
            raise ValueError('Invalid reviewed vocabulary entry')
        aliases = entry.get('aliases', [])
        if not isinstance(aliases, list) or any(not isinstance(a, str) for a in aliases):
            raise ValueError('Invalid reviewed aliases')
        result.append(entry)
    return result

def export_vocabulary(registry, target, include_aliases=False):
    entries = {}
    for entry in reviewed_entries(load(registry)):
        key = (entry['kind'], canon(entry['name']))
        if key not in entries:
            entries[key] = dict(kind=entry['kind'], name=entry['name'], aliases=[],
                                review='confirmed', subtype=entry.get('subtype', ''), source_ids=[])
        row = entries[key]
        row['source_ids'].append(entry['id'])
        if include_aliases:
            row['aliases'] = sorted(set(row['aliases'] + entry.get('aliases', [])))
    write(target, dict(schema_version=1, purpose='Deliberate human-reviewed vocabulary export',
                       source_sha256=sha(registry.read_bytes()), aliases_explicitly_included=include_aliases,
                       entries=list(entries.values())))

def evidence(method, label, text, start, end, score=None, model='', revision=''):
    if not 0 <= start < end <= len(text): raise ValueError('Invalid extraction span')
    return dict(method=method, label=label, score=score, start=start, end=end,
                offset_unit='unicode_code_points', extractor_version=VERSION,
                model=model, model_revision=revision)

def make_anchor(guid, edition, passage, start, end, extraction):
    return dict(guid=guid, edition=edition, passage_id=passage['id'], passage_text=passage['text'],
                quote=passage['text'][start:end], extraction=[extraction])

def retain_anchor(anchors, anchor):
    for existing in anchors:
        if all(existing[k] == anchor[k] for k in ('guid','edition','passage_id','quote','passage_text')):
            for item in anchor['extraction']:
                if item not in existing['extraction']: existing['extraction'].append(item)
            return
    anchors.append(anchor)

def reference_mentions(passages, guid, edition):
    groups = []
    for i, passage in enumerate(passages):
        hits = list(CUES.finditer(passage['text']))
        if not hits: continue
        anchors = [make_anchor(guid, edition, passage, h.start(), h.end(),
                   evidence('reference-cue', h.group().casefold(), passage['text'], h.start(), h.end())) for h in hits]
        # Adjacent mentions form review context, not a claim that they denote one work.
        if groups and i - groups[-1]['last_position'] <= 1:
            groups[-1]['anchors'].extend(anchors)
            groups[-1]['last_position'] = i
            groups[-1]['context'] = passages[max(0, groups[-1]['first_position']-1):min(len(passages), i+2)]
        else:
            groups.append(dict(first_position=i, last_position=i, status='unidentified',
                reason='Reference keyword alone does not identify a publication or establish authorship.',
                anchors=anchors, context=passages[max(0, i-1):i+2]))
    for group in groups:
        group['id'] = 'mention:' + sha((guid+'\0'+edition+'\0'+str(group['anchors'][0]['passage_id'])).encode())[:24]
        group.pop('first_position'); group.pop('last_position')
    return groups

def publication_supported(passages, position):
    context = ' '.join(p['text'] for p in passages[max(0, position-1):position+2])
    return bool(PUBLICATION_CONTEXT.search(context))

def main():
    project = Path(sys.argv[1]); parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--model', choices=['urchade/gliner_small-v2.1','urchade/gliner_large-v2.1'], default=MODEL)
    parser.add_argument('--revision', help='Cached model commit; required for reproducible comparisons')
    parser.add_argument('--package', type=Path); parser.add_argument('--edition')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--export-vocabulary', type=Path, metavar='REGISTRY')
    parser.add_argument('--include-aliases', action='store_true')
    args = parser.parse_args(sys.argv[2:])
    model_name = args.model
    vocabulary_path = project/'data/reviewed_index_vocabulary.json'
    if args.export_vocabulary:
        if not args.output: parser.error('--output required for explicit vocabulary export')
        if args.export_vocabulary.resolve() == args.output.resolve(): parser.error('Export must not overwrite registry')
        export_vocabulary(args.export_vocabulary, args.output, args.include_aliases)
        print('Reviewed vocabulary exported; review before installing at data/reviewed_index_vocabulary.json.'); return
    from gliner import GLiNER
    import torch
    cache = Path(os.environ['HF_HOME'])/('hub/models--'+model_name.replace('/','--'))
    snapshots = sorted(cache.glob('snapshots/*/gliner_config.json'))
    if not snapshots: raise SystemExit('Offline local indexing model missing. Restore model-cache before preparation.')
    vocab_bytes = vocabulary_path.read_bytes()
    vocab_hash = sha(vocab_bytes)
    vocab = reviewed_entries(json.loads(vocab_bytes))
    # Pin the loaded local snapshot to the revision recorded in occurrence evidence.
    snapshot = snapshots[-1].parent
    if args.revision:
        selected = [p.parent for p in snapshots if p.parent.name == args.revision]
        if not selected: raise SystemExit('Requested model revision is not cached.')
        snapshot = selected[0]
    if args.check: print('Offline local indexing environment and reviewed vocabulary ready.'); return
    if not args.package or not args.output: parser.error('--package and --output required')
    package = args.package.resolve(); out = args.output.resolve(); started = time.perf_counter()
    m = load(package/'episode.json'); guid = m['episode_guid']; edition = args.edition or m['audio']['identity']
    def artifact(relative):
        path = (package/relative).resolve()
        if not path.is_relative_to(package): raise ValueError('Unsafe package path')
        data = path.read_bytes(); record = next((r for r in m['artifacts'] if r['file']==relative), None)
        if not record or sha(data)!=record['sha256']: raise ValueError('Transcript artifact checksum mismatch')
        return data
    base_bytes = artifact(m['transcript']['reviewed_file']); base = json.loads(base_bytes)
    alignment = json.loads(artifact(m['transcript']['alignment_file']))
    if alignment['source_transcript_sha256']!=sha(base_bytes) or alignment['audio_identity']!=m['audio']['identity'] or base['episode_guid']!=guid:
        raise ValueError('Transcript/audio identity mismatch')
    passages = base['segments']; by_id = {p['id']: p for p in passages}
    if len(by_id)!=len(passages) or len(alignment['segments'])!=len(passages): raise ValueError('Invalid passage coverage')
    terms = collections.defaultdict(list)
    for entry in vocab:
        for term in {canon(x) for x in [entry['name'], *entry.get('aliases', [])] if len(x.strip())>=3}:
            terms[term].append(entry)
    pattern = re.compile(r'(?<!\w)(?:'+'|'.join(re.escape(x).replace(r'\ ',r'\s+') for x in sorted(terms,key=lambda x:(-len(x),x)))+r')(?!\w)', re.I) if terms else None
    entries = {}
    def add(kind, name, passage, start, end, extraction, subtype=''):
        normalized = canon(name)
        if len(normalized)<3 or normalized in BLOCKED or (kind=='place' and normalized in TIME_TERMS): return
        key = (kind, normalized); quote = passage['text'][start:end]
        if key not in entries:
            entries[key] = dict(id='local:'+sha((guid+'\0'+kind+'\0'+normalized).encode())[:24],
                kind=kind,name=name,review='suggested',aliases=[],subtype=subtype or ('person' if kind=='author' else ''),
                year=None,publication='',doi='',url='',link_verified=False,author_ids=[],anchors=[],note='Offline local suggestion; requires review.',
                details=dict(spoken=[],description='Local candidate; person detection does not establish authorship. Publication metadata is unverified.',
                    confidence='unreviewed',normalizations=[],editorial_note='Extraction scores are model evidence, not human confirmation.',
                    bibliography='',original_publication='',sources=[],model=model_name))
        entry = entries[key]
        if quote not in entry['aliases']: entry['aliases'].append(quote)
        if quote not in entry['details']['spoken']: entry['details']['spoken'].append(quote)
        retain_anchor(entry['anchors'], make_anchor(guid,edition,passage,start,end,extraction))
    for passage in passages:
        for hit in pattern.finditer(passage['text']) if pattern else []:
            for entry in terms[canon(hit.group())]:
                add(entry['kind'],entry['name'],passage,hit.start(),hit.end(),
                    evidence('reviewed-dictionary',entry['kind'],passage['text'],hit.start(),hit.end(),
                             revision=vocab_hash),entry.get('subtype',''))
    torch.set_num_threads(4); device = 'mps' if torch.backends.mps.is_available() else 'cpu'
    model = GLiNER.from_pretrained(str(snapshot),local_files_only=True).to(device); model.eval()
    model_version = importlib.metadata.version('gliner')
    labels = {'taxon':'fossil','animal group':'fossil','plant group':'fossil','place':'place','geological formation':'place','person':'author','research paper title':'paper','article title':'article'}
    pending_titles = []
    for batch_start in range(0,len(passages),8):
        batch = passages[batch_start:batch_start+8]
        with torch.inference_mode(): predictions = model.inference([p['text'] for p in batch],list(labels),threshold=.5,flat_ner=False)
        for position,(passage,hits) in enumerate(zip(batch,predictions),batch_start):
            for hit in hits:
                text=passage['text']; a,z=hit['start'],hit['end']; kind=labels[hit['label']]
                if not 0<=a<z<=len(text) or text[a:z]!=hit['text']: raise ValueError('Invalid model span')
                if (a and text[a-1].isalnum()) or (z<len(text) and text[z].isalnum()): continue
                source=evidence('gliner',hit['label'],text,a,z,float(hit['score']),model_name,snapshot.name)
                source['extractor_version'] += '/gliner-'+model_version
                if kind in ('paper','article') and not publication_supported(passages,position):
                    pending_titles.append(dict(status='unidentified',
                        id='mention:'+sha((guid+'\0'+edition+'\0'+str(passage['id'])+'\0'+str(a)).encode())[:24],
                        reason='Possible model title without supporting publication or attribution cues.',
                        anchors=[make_anchor(guid,edition,passage,a,z,source)],
                        context=passages[max(0,position-1):position+2]))
                    continue
                add(kind,hit['text'],passage,a,z,source)
        if batch_start%80==0: print('LOCAL_INDEX_PROGRESS '+str(min(batch_start+8,len(passages)))+' '+str(len(passages)),flush=True)
    mentions=reference_mentions(passages,guid,edition) + pending_titles
    document = dict(schema_version=1, entries=list(entries.values()), unidentified_reference_mentions=mentions)
    document, recovered = recover_publications(document, {(guid,edition):{p['id']:p['text'] for p in passages}})
    document, suppressed = apply_blacklist(document, load_blacklist(project))
    document['entries'].sort(key=lambda e:(e['kind'],e['name'].casefold()))
    write(out/'index.json', document)
    entries = {e['id']:e for e in document['entries']}

    summary=dict(schema_version=1,episode_guid=guid,edition=edition,title=m['metadata']['title'],passages=len(passages),entries=len(entries),
        categories={k:sum(e['kind']==k for e in entries.values()) for k in KINDS},unidentified_reference_mentions=len(mentions),
        seconds=round(time.perf_counter()-started,2),method='reviewed dictionary + offline GLiNER; unidentified reference mentions retained separately',
        extractor_version=VERSION,gliner_version=model_version,model=model_name,model_revision=snapshot.name,threshold=.5,device=device,paid_api_calls=0,
        vocabulary_sha256=vocab_hash,reviewed_vocabulary_entries=len(vocab),index_sha256=sha((out/'index.json').read_bytes()),
        baseline_sha256=sha(base_bytes),audio_identity=m['audio']['identity'],review_required=True,
        recovered_publication_candidates=recovered,blacklisted_entries=suppressed,
        notes='Attributed references are descriptive, unverified publication candidates; generic mentions remain separate. Model scores do not confirm names, categories or authorship.')
    write(out/'summary.json',summary); print(json.dumps(summary),flush=True)

if __name__ == '__main__': main()
PY_INDEX

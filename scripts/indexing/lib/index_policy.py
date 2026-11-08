"""Publication recovery and deletion policy shared by ZSH indexing entry points."""
import copy, hashlib, json, re
from pathlib import Path

VERSION = 'index-policy-1'
KINDS = {'fossil', 'place', 'paper', 'article', 'author'}


def heading(value):
    # Match app filing equivalence, including older '<name>, The' records.
    value = re.sub(r',\s*the$', '', value.strip(), flags=re.I).strip()
    return re.sub(r'^the\s+', '', value, flags=re.I).strip()


def key(value):
    return ' '.join(heading(value).lower()
                    .replace('–', '-').replace('—', '-').replace('‑', '-')
                    .replace('’', "'").split())


def deletion_records(document):
    if not isinstance(document, dict) or document.get('schema_version') != 1 or not isinstance(document.get('entries'), list):
        raise ValueError('Invalid deletion blacklist schema')
    result = []
    for e in document['entries']:
        if not isinstance(e, dict):
            raise ValueError('Invalid deleted index entry')
        if not e.get('deleted'):
            continue
        if (e.get('deleted') is not True or e.get('kind') not in KINDS
                or not isinstance(e.get('id'), str) or not e['id'] or len(e['id']) > 1000
                or not isinstance(e.get('name'), str) or not e['name'].strip() or len(e['name']) > 1000):
            raise ValueError('Invalid deleted index entry')
        for field in ('aliases', 'variant_ids'):
            if not isinstance(e.get(field, []), list) or any(not isinstance(v, str) or len(v) > 1000 for v in e.get(field, [])):
                raise ValueError('Invalid deletion aliases/IDs')
        result.append(dict(id=e['id'], kind=e['kind'], name=e['name'], deleted=True,
                           aliases=e.get('aliases', []), variant_ids=e.get('variant_ids', [])))
    return result


def load_blacklist(root):
    path = Path(root) / 'data/index_deletion_blacklist.json'
    return deletion_records(json.loads(path.read_text())) if path.exists() else []


def blocked(entry, records):
    ids = {entry['id'], *entry.get('variant_ids', [])}
    return any(ids.intersection({e['id'], *e.get('variant_ids', [])}) or
               (entry['kind'] == e['kind'] and key(entry['name']) in
                {key(e['name']), *(key(a) for a in e.get('aliases', []))}) for e in records)


def apply_blacklist(document, records):
    result = copy.deepcopy(document)
    count = 0
    for e in result['entries']:
        if not e.get('deleted') and blocked(e, records):
            e['deleted'] = True
            count += 1
    return result, count


def recover_publications(document, baselines):
    """Promote attributed mentions, never a generic 'study' cue alone.

    Labels describe the known attribution; they do not claim to be paper titles.
    Every context quote must still match the supplied edition's exact baseline.
    """
    result = copy.deepcopy(document)
    ids = {e['id'] for e in result['entries']}
    recovered = 0
    for mention in result.get('unidentified_reference_mentions', []):
        if not mention.get('anchors'):
            continue
        first = mention['anchors'][0]
        baseline = baselines.get((first.get('guid'), first.get('edition')), {})
        anchors = [a for a in mention['anchors'] if a.get('guid') == first.get('guid')
                   and a.get('edition') == first.get('edition')
                   and a.get('passage_text') == baseline.get(a.get('passage_id'))
                   and isinstance(a.get('quote'), str) and a['quote'] and a['quote'] in a['passage_text']]
        if not anchors:
            continue
        context = [c for c in mention.get('context', []) if c.get('text') == baseline.get(c.get('id'))]
        text = ' '.join(c['text'] for c in context)
        # Retain exact transcript spellings; source/API stages may propose correction.
        author = re.search(r'\bby\s+([A-Z][\w’\'-]*(?:\s+[A-Z][\w’\'-]*){0,3})\s+et\s+al\.?', text)
        if not author:
            author = re.search(r'\b(?:study|paper|article|research)\s+(?:(?:is|was|written|authored)\s+)?by\s+([A-Z][\w’\'-]*(?:\s+[A-Z][\w’\'-]*){0,3})', text)
        journal = re.search(r'\b(?:published\s+in|(?:study|paper|article)\s+(?:is\s+)?in)\s+([A-Z][\w, &–-]{1,100}?)(?=\s+by\b|[.!?]|$)', text)
        named_title = any(x.get('label') in ('research paper title', 'article title')
                          for a in anchors for x in a.get('extraction', []))
        named_title = named_title and bool(re.search(r'\b(titled|entitled|published|journal)\b', text, re.I))
        if not (author or journal or named_title):
            continue
        kind = 'article' if re.search(r'\barticle\s+(?:is\s+)?(?:in|by)\b', text, re.I) else 'paper'
        if author:
            suffix = ' et al.' if re.search(re.escape(author[1]) + r'\s+et\s+al\b', text) else ''
            name = ('Article' if kind == 'article' else 'Study') + ' attributed to ' + author[1] + suffix
        elif journal:
            name = 'Research published in ' + journal[1].strip(' ,')
        else:
            name = anchors[0]['quote']
        token = first.get('guid', '') + '\0' + first.get('edition', '') + '\0' + mention['id']
        ident = 'reference:' + hashlib.sha256(token.encode()).hexdigest()[:24]
        mention['candidate_id'] = ident
        if ident in ids:
            continue
        # Reuse a real title candidate already extracted in these same passages.
        pids = {a['passage_id'] for a in anchors}
        existing = next((e for e in result['entries'] if e['kind'] in ('paper', 'article')
                         and any(a.get('guid') == first['guid'] and a.get('edition') == first['edition']
                                 and a.get('passage_id') in pids for a in e.get('anchors', []))), None)
        if existing:
            mention['candidate_id'] = existing['id']
            continue
        # Exact adjacent passages are evidence too: attribution can cross a boundary.
        for c in context:
            if not any(a['passage_id'] == c['id'] for a in anchors):
                anchors.append(dict(guid=first['guid'], edition=first['edition'], passage_id=c['id'],
                                    passage_text=c['text'], quote=c['text']))
        result['entries'].append(dict(id=ident, kind=kind, name=name, review='suggested',
            aliases=[], subtype='unidentified_publication', year=None, publication='', doi='', url='',
            link_verified=False, author_ids=[], anchors=anchors,
            note='Publication reference retained from transcript attribution; exact identity requires review.',
            details=dict(spoken=[a['quote'] for a in mention['anchors']],
                description='Attribution/context from the transcript: ' + text,
                confidence='unreviewed', normalizations=[], sources=[], model=VERSION,
                editorial_note='Descriptive label, not a verified publication title. Author/journal spellings may be transcription errors.')))
        ids.add(ident)
        recovered += 1
    return result, recovered


def merge_blacklist(root, document):
    """Append deletion decisions under a process lock; never erase old names."""
    import fcntl, os, datetime
    path = Path(root) / 'data/index_deletion_blacklist.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    additions = deletion_records(document)
    with path.with_suffix('.json.lock').open('a') as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX)
        old = json.loads(path.read_text()) if path.exists() else dict(schema_version=1, entries=[])
        deletion_records(old)
        rows = list(old['entries'])
        # Include metadata in identity so later renamed/deleted forms remain recorded.
        seen = {json.dumps({k:e.get(k, []) for k in ('id','kind','name','aliases','variant_ids')}, sort_keys=True) for e in rows}
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        for entry in additions:
            token = json.dumps({k:entry.get(k, []) for k in ('id','kind','name','aliases','variant_ids')}, sort_keys=True)
            if token not in seen:
                rows.append(dict(entry, recorded_at_utc=now))
                seen.add(token)
        pending = path.with_name(path.name + '.pending')
        with pending.open('w') as f:
            json.dump(dict(schema_version=1, entries=rows), f, indent=2, ensure_ascii=False)
            f.write('\n'); f.flush(); os.fsync(f.fileno())
        pending.replace(path)
        # Bundle the same durable history for app-side manual additions.
        asset = Path(root) / 'flutter_app/assets/data/index_deletion_blacklist.json'
        if asset.parent.is_dir():
            snapshot = asset.with_name(asset.name + '.pending')
            snapshot.write_bytes(path.read_bytes())
            snapshot.replace(asset)
    return len(rows)

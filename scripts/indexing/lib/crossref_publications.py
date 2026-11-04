"""Conservative Crossref publication resolution and linked bibliographic authors."""
import datetime, hashlib, html, json, re, unicodedata
from pathlib import Path


def plain(value):
    return html.unescape(re.sub(r'<[^>]*>', '', value or '')).strip()


def normalized(value):
    text = unicodedata.normalize('NFKD', plain(value).lower())
    return ' '.join(re.findall(r'\w+', ''.join(c for c in text if not unicodedata.combining(c))))


def journal_key(value):
    text = normalized(value).replace(' and ', ' ')
    text = text.replace(' & ', ' ')
    aliases = {'pier j': 'peerj', 'peer j': 'peerj', 'paleos': 'palaios',
               'p3': 'palaeogeography palaeoclimatology palaeoecology'}
    return aliases.get(text, text)


def title_terms(value):
    stop = set('a an the of and or in on for to by from with as is are their its all other new study research relationships placement group'.split())
    return {w[:8].rstrip('s') for w in normalized(value).split() if len(w) > 3 and w not in stop}


def publication_context(policy, anchors):
    pieces = {}
    for a in anchors:
        base = policy.baselines.get((a['guid'], a['edition']), {})
        for pid in range(a['passage_id'] - 10, a['passage_id'] + 11):
            if pid in base:
                pieces[(a['guid'], a['edition'], pid)] = base[pid]
    return ' '.join(pieces[k] for k in sorted(pieces))


def valid_dates(candidate):
    dates = []
    for values in candidate.get('dates', {}).values():
        for parts in values:
            if not isinstance(parts, list) or not parts or type(parts[0]) is not int:
                continue
            try:
                dates.append(datetime.date(*(parts + [1, 1])[:3]))
            except (ValueError, TypeError):
                pass
    return dates


def context_match(candidate, context, cutoff):
    """Require author + explicit journal + subject + date, independently of rank."""
    if re.match(r'(?i)^(author )?(correction|erratum|corrigendum|retraction)\b', candidate['title']):
        return None
    if candidate.get('crossref_type') not in ('journal-article', 'proceedings-article'):
        return None
    authors = candidate.get('authors', [])
    if not any(a.get('family') and re.search(r'\b' + re.escape(normalized(a['family'])) + r'\b', normalized(context)) for a in authors):
        return None
    journal = journal_key(candidate.get('journal', ''))
    # Check actual spoken journal phrases, never topical occurrence of a word
    # such as Nature anywhere in an unrelated passage.
    phrases = re.findall(r'(?i)(?:published\s+in|article\s+(?:is\s+)?in|et\s+al\.?\s+in)\s+(.{2,120}?)(?=\s+by\b|\s+says\b|[.!?]|$)', context)
    if not journal or not any(journal_key(p.strip(' ,')) == journal for p in phrases):
        return None
    overlap = sorted(title_terms(candidate['title']) & title_terms(context))
    if len(overlap) < 2:
        return None
    dates = valid_dates(candidate)
    if not cutoff or not dates or min(dates) > datetime.date.fromisoformat(cutoff[:10]):
        return None
    return dict(method='author-journal-subject-date', matched_subject_terms=overlap,
                journal=candidate['journal'], earliest_date=str(min(dates)))


def resolve_publication(policy, group, anchors):
    e = max(group, key=lambda x: len(policy.valid_anchors(x)))
    context = publication_context(policy, anchors)
    cutoff = getattr(policy, 'publication_cutoff', '')
    pins_path = policy.root / 'data/publication_reference_matches.json'
    pins = json.loads(pins_path.read_text()).get('matches', []) if pins_path.exists() else []
    pin = next((p for p in pins if any(a['guid'] == p['episode_guid'] and a['passage_id'] == p['passage_id']
        and hashlib.sha256(a['passage_text'].encode()).hexdigest() == p['passage_text_sha256'] for a in anchors)), None)
    doi = next((x.get('doi') for x in group if x.get('doi')), None) or (pin['doi'] if pin else None)
    query = e['name'] if e.get('subtype') != 'unidentified_publication' else e['name'] + ' ' + context
    query = query[:950]
    url = policy.cr['query_url']({'doi': doi} if doi else {'query': query, 'rows': 5}, '')
    response = policy.fetch('crossref', url)
    message = response['payload'].get('message', {})
    items = [message] if doi else message.get('items', [])
    candidates = []
    for item in items:
        c = policy.cr['metadata'](item, cutoff)
        c['title'] = plain(c['title']); c['journal'] = plain(c['journal'])
        if c['doi'] and c['title'] and not any(x['doi'].lower() == c['doi'].lower() for x in candidates):
            candidates.append(c)
    selected = []
    for c in candidates:
        proof = None
        if doi and c['doi'].lower() == doi.lower():
            proof = dict(method='contextually-identified-doi' if pin else 'stored-doi')
            if pin:
                proof.update(reason=pin['reason'], corroborating_sources=pin['sources'])
        elif len(normalized(c['title']).split()) >= 5 and normalized(c['title']) in normalized(context + ' ' + e['name']):
            proof = dict(method='complete-title')
        else:
            proof = context_match(c, context, cutoff)
        if proof:
            selected.append((c, proof))
    if len(selected) == 1:
        c, proof = selected[0]
        return dict(status='applied', target_name=c['title'], reason='Crossref publication identity: ' + proof['method'],
            matched=[dict(provider='crossref', record=c, retrieved_at_utc=response['retrieved_at_utc'],
                          request_url=response['request_url'], match_evidence=proof)], candidates=candidates)
    return dict(status='hard_unresolved', reason='Publication clues do not uniquely identify one work; candidate titles/authors retained for review',
                candidates=candidates, matched=[])


def author_name(author):
    return plain(author.get('name') or ' '.join(x for x in [author.get('given', ''), author.get('family', '')] if x))


def attach_authors(document, confirmations, valid_anchors, blocked):
    """Coauthors are sourced bibliography, never claims of spoken name mentions."""
    publications = [e for e in document['entries'] if e['kind'] in ('paper', 'article') and not e.get('deleted') and e.get('review') != 'rejected']
    for pub in publications:
        if blocked(pub):
            continue
        raw = (pub.get('details') or {}).get('bibliography', '')
        try:
            citation = json.loads(raw) if raw else {}
        except (ValueError, TypeError):
            continue
        if not isinstance(citation, dict) or citation.get('status') != 'source_confirmed':
            continue
        links = []
        anchors = valid_anchors(pub)
        if not anchors:
            continue
        for author in citation.get('authors', []):
            name = author_name(author)
            if not name:
                continue
            ident = 'crossref-author:' + hashlib.sha256((author.get('orcid') or citation['doi'] + '\0' + normalized(name)).encode()).hexdigest()[:24]
            entry = next((e for e in document['entries'] if e['kind'] == 'author' and normalized(e['name']) == normalized(name) and not e.get('deleted') and e.get('review') != 'rejected'), None)
            if entry is None:
                entry = dict(id=ident,kind='author',name=name,review='suggested',aliases=[],subtype='publication_author',
                    year=None,publication='',doi='',url='',link_verified=False,author_ids=[],anchors=list(anchors),
                    note='Bibliographic author supplied by Crossref for a matched publication; the name may not be spoken in the podcast.',
                    details=dict(spoken=[],confidence='source_metadata',description='Author of ' + citation['title'],
                        normalizations=[],editorial_note='Reference passages identify the publication. Coauthorship is source metadata, not a transcript-name occurrence.',
                        model='',sources=[dict(url=citation['url'],label='Crossref — publication authors')]))
                if blocked(entry):
                    continue
                document['entries'].append(entry)
            elif blocked(entry):
                continue
            if entry.get('subtype') == 'publication_author':
                for a in anchors:
                    if a not in entry['anchors']:
                        entry['anchors'].append(a)
                confirmations[entry['id']] = ['crossref']
            links.append(entry['id'])
        pub['author_ids'] = list(dict.fromkeys(links + pub.get('author_ids', [])))

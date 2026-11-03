#!/bin/zsh
# Cached, evidence-validated episode extraction; app publication is a separate export.
set -euo pipefail
trial_project="${0:A:h:h}"
trial_python="${INDEX_TRIAL_PYTHON:-python3}"
exec "$trial_python" - "$trial_project" "$@" <<'PY_TRIAL'
from pathlib import Path
from datetime import datetime,timezone
import argparse,collections,hashlib,json,os,re,stat,sys,time,urllib.error,urllib.request

project=Path(sys.argv[1]);parser=argparse.ArgumentParser(description='Prepare/run cached contextual extraction (Karoo trial or --package).')
parser.add_argument('--run',action='store_true',help='Make paid API requests; completed responses are reused.')
parser.add_argument('--prepare-only',action='store_true',help='Freeze current inputs without API calls (default).')
parser.add_argument('--reprocess-only',action='store_true',help='Revalidate cached responses without any API call or credential.')
parser.add_argument('--model',default='gpt-6-astra')
parser.add_argument('--package',type=Path,help='Index a validated episode package instead of the Karoo trial; requires --output.')
parser.add_argument('--max-usd',type=float,default=5.0)
parser.add_argument('--chunk-size',type=int,default=100)
parser.add_argument('--overlap',type=int,default=8)
parser.add_argument('--max-output-tokens',type=int,default=12000)
parser.add_argument('--key-file',type=Path,default=project/'work/indexing-trial/openai-api-key')
parser.add_argument('--output',type=Path,default=project/'outputs/indexing-trial/episode-208-karoo')
args=parser.parse_args(sys.argv[2:])
if sum([args.run,args.prepare_only,args.reprocess_only])>1: parser.error('Choose --run, --prepare-only or --reprocess-only.')
if not 20<=args.chunk_size<=150 or not 0<=args.overlap<args.chunk_size: parser.error('Invalid chunk size/overlap.')
if not 1000<=args.max_output_tokens<=20000 or not 0<args.max_usd<=20: parser.error('Invalid request/spend bounds.')
outputs=args.output.resolve();outputs.mkdir(parents=True,exist_ok=True)
if args.package and '--output' not in sys.argv: parser.error('--package requires its own --output directory.')
import fcntl
run_lock=(outputs/'.indexing.lock').open('a')
try: fcntl.flock(run_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise SystemExit('This index output is already in use.')
helpers=project/'scripts/indexing_trial';guid='commondescentpodcast.podbean.com/870afb21-277f-398e-ba55-6e50d68ceda6'

def sha(data): return hashlib.sha256(data).hexdigest()
def read_json(path): return json.loads(path.read_text())
def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    pending=path.with_suffix(path.suffix+'.pending');pending.write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n');pending.replace(path)
def immutable(path,value):
    if path.exists():
        if read_json(path)!=value: raise SystemExit(f'Frozen configuration changed: {path.name}. Use a new --output directory; previous results preserved.')
    else: write_json(path,value)
def stamp(ms): return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}'
def canonical(value): return re.sub(r'\s+',' ',value.casefold().replace('–','-').replace('—','-')).strip()

if args.package:
    guid=read_json(args.package.resolve()/'episode.json')['episode_guid']

def snapshot_source():
    index=project/'work/episode-preparation/library.json'
    entry=read_json(index).get(guid) if index.exists() else None
    package=args.package.resolve() if args.package else project/entry['package'] if entry else project/'flutter_app/assets/episodes/870afb21-277f-398e-ba55-6e50d68ceda6'
    if args.package and (not entry or (project/entry['package']).resolve()!=package): entry=None
    manifest=read_json(package/'episode.json');identity=manifest['audio']['identity']
    if manifest['episode_guid']!=guid: raise SystemExit('Wrong episode package.')
    def artifact(relative):
        path=(package/relative).resolve()
        if not path.is_relative_to(package.resolve()): raise SystemExit('Unsafe package path.')
        record=next((a for a in manifest['artifacts'] if a['file']==relative),None)
        data=path.read_bytes()
        if not record or sha(data)!=record['sha256']: raise SystemExit('Package artifact checksum mismatch: '+relative)
        return data
    base_bytes=artifact(manifest['transcript']['reviewed_file']);alignment_bytes=artifact(manifest['transcript']['alignment_file'])
    baseline=json.loads(base_bytes);alignment=json.loads(alignment_bytes)
    if alignment['source_transcript_sha256']!=sha(base_bytes) or alignment['audio_identity']!=identity:
        raise SystemExit('Alignment identity mismatch.')
    if len(baseline['segments'])!=len(alignment['segments']): raise SystemExit('Incomplete alignment coverage.')
    edition=entry['edition'] if entry else identity
    name=guid.encode().hex()+'.json'
    support_roots=[Path.home()/'Library/Containers/com.example.commonDescentListing/Data/Library/Application Support/com.example.commonDescentListing',Path.home()/'Library/Application Support/com.example.commonDescentListing']
    journals=[root/'transcript-edits'/('editions/'+edition if entry else '')/name for root in support_roots]
    present=[p for p in journals if p.exists()]
    if len(present)>1: raise SystemExit('Multiple matching-edition correction journals; resolve explicitly before trial.')
    journal_bytes=present[0].read_bytes() if present else None
    journal=json.loads(journal_bytes) if journal_bytes else None
    text={s['id']:s['text'] for s in baseline['segments']};base={s['id']:s for s in baseline['segments']}
    offset=0;revisions=[]
    if journal:
        if journal.get('schema_version')!=1 or journal.get('episode_guid')!=guid or not isinstance(journal.get('revisions'),list): raise SystemExit('Invalid correction journal.')
        offset=journal.get('sync_offset_ms',0)
        if journal.get('sync_offset_audio_identity','legacy-stream')!=identity: offset=journal.get('sync_offsets_ms',{}).get(identity,0)
        if not isinstance(offset,int) or abs(offset)>600000: raise SystemExit('Invalid saved offset.')
        revisions=journal['revisions']
        for revision in revisions:
            cue=base.get(revision['cue_id'])
            if not cue or cue['start_ms']!=revision['start_ms'] or cue['end_ms']!=revision['end_ms'] or cue['text']!=revision['baseline_text'] or text[cue['id']]!=revision['before']:
                raise SystemExit('Corrections no longer match this baseline; no API request sent.')
            text[cue['id']]=revision['after']
    passages=[];previous=0
    for cue,row in zip(baseline['segments'],alignment['segments']):
        if cue['id']!=row['id'] or cue['text']!=row['baseline_text'] or (cue['start_ms'],cue['end_ms'])!=(row['source_start_ms'],row['source_end_ms']) or not previous<=row['start_ms']<row['end_ms']<=alignment['audio_duration_ms']:
            raise SystemExit('Invalid passage alignment.')
        previous=row['end_ms']
        passages.append(dict(id=cue['id'],text=text[cue['id']],start_ms=row['start_ms'],end_ms=row['end_ms'],audio_start_ms=max(0,row['start_ms']-offset)))
    return dict(schema_version=1,episode_guid=guid,episode_number=manifest.get('metadata',{}).get('number','208'),episode_title=manifest.get('metadata',{}).get('title','The Karoo Supergroup'),edition=edition,
        audio_identity=identity,package=str(package.relative_to(project)),baseline_sha256=sha(base_bytes),alignment_sha256=sha(alignment_bytes),
        correction_journal_sha256=sha(journal_bytes) if journal_bytes else None,revision_count=len(revisions),sync_offset_ms=offset,
        transcript_label=baseline['review']['label'],passages=passages)

source=snapshot_source();immutable(outputs/'source_snapshot.json',source)
prompt=(helpers/'prompt.txt').read_text();schema=read_json(helpers/'schema.json');pricing=read_json(helpers/'pricing.json')
if args.model not in pricing['models']: raise SystemExit('No reviewed pricing for requested model; add explicit rates before running.')
rates=pricing['models'][args.model]
config=dict(schema_version=1,model=args.model,reasoning_effort='medium',chunk_size=args.chunk_size,overlap=args.overlap,max_output_tokens=args.max_output_tokens,
    source_sha256=sha(json.dumps(source,sort_keys=True).encode()),prompt_sha256=sha(prompt.encode()),schema_sha256=sha(json.dumps(schema,sort_keys=True).encode()),
    pricing=pricing,max_usd=args.max_usd,endpoint='https://api.openai.com/v1/responses')
immutable(outputs/'config.json',config)
for name,value in [('prompt.txt',prompt),('schema.json',json.dumps(schema,indent=2)+'\n')]:
    path=outputs/name
    if path.exists() and path.read_text()!=value: raise SystemExit('Frozen prompt/schema changed.')
    path.write_text(value)
passages=source['passages'];by_id={p['id']:p for p in passages}
chunks=[passages[i:i+args.chunk_size] for i in range(0,len(passages),args.chunk_size-args.overlap)]
write_json(outputs/'prepared.json',dict(passages=len(passages),chunks=len(chunks),model=args.model,max_usd=args.max_usd,
    ready_for_api=True,accepted_app_registry_changed=False,review_sample_exists=(outputs/'manual-sample.json').exists()))
print(f'Prepared {len(passages)} passages in {len(chunks)} chunks from edition {source["edition"]}.',flush=True)
if not args.run and not args.reprocess_only:
    print('Preparation only; no paid API requests made.',flush=True);raise SystemExit(0)
if not args.package and not (outputs/'manual-sample.json').exists(): raise SystemExit('Independent manual-sample.json must be written before API extraction.')
key=''
if not args.reprocess_only:
    if args.key_file.exists():
        if stat.S_IMODE(args.key_file.stat().st_mode)&0o077: raise SystemExit('Trial key file must have mode 600.')
        key=args.key_file.read_text().strip()
    else: key=os.environ.get('OPENAI_API_KEY','').strip()
    if not key: raise SystemExit('No API credential. Run scripts/configure_indexing_key.zsh in Terminal.')
def request_json(path,payload=None):
    data=json.dumps(payload,ensure_ascii=False).encode() if payload is not None else None
    request=urllib.request.Request('https://api.openai.com/v1/'+path,data=data,headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(request,timeout=240) as response:
            return json.load(response),response.headers.get('x-request-id')
    except urllib.error.HTTPError as error:
        try: body=json.loads(error.read()).get('error',{})
        except Exception: body={}
        # Never retain credential-echoing server error messages.
        safe=dict(http_status=error.code,error_type=body.get('type'),error_code=body.get('code'),path=path)
        write_json(outputs/'api-error.json',safe)
        raise SystemExit(f'OpenAI request failed: HTTP {error.code}, code {body.get("code")}. No automatic retry.')
    except (TimeoutError,urllib.error.URLError):
        write_json(outputs/'api-error.json',dict(error_type='transport_or_timeout',path=path,possible_unrecorded_billable_request=payload is not None))
        raise SystemExit('API transport/timeout error. No automatic retry: inspect usage before resuming.')

if not args.reprocess_only:
    models,_=request_json('models')
    if args.model not in {m['id'] for m in models['data']}: raise SystemExit('Selected model unavailable to this API project; no substitution made.')

def cost(usage):
    tokens=usage.get('input_tokens',0);cached=usage.get('input_tokens_details',{}).get('cached_tokens',0);out=usage.get('output_tokens',0)
    writes=usage.get('input_tokens_details',{}).get('cache_write_tokens',0)
    if tokens-cached-writes<0: raise SystemExit('Unexpected overlapping token categories; review billing.')
    return ((tokens-cached-writes)*rates['input_per_million']+writes*rates['input_per_million']*1.25+cached*rates['cached_input_per_million']+out*rates['output_per_million'])/1000000

def validate(value,spec,path='document'):
    if 'anyOf' in spec:
        for option in spec['anyOf']:
            try: validate(value,option,path);return
            except ValueError: pass
        raise ValueError(path+': no valid schema branch')
    kinds=spec.get('type');kinds=kinds if isinstance(kinds,list) else [kinds]
    valid=any((k=='object' and isinstance(value,dict)) or (k=='array' and isinstance(value,list)) or (k=='string' and isinstance(value,str)) or (k=='integer' and type(value) is int) or (k=='boolean' and type(value) is bool) or (k=='null' and value is None) for k in kinds)
    if not valid or ('enum' in spec and value not in spec['enum']): raise ValueError(path+': type/enum mismatch')
    if isinstance(value,dict):
        if set(value)!=set(spec['required']): raise ValueError(path+': missing/extra fields')
        for name,item in value.items(): validate(item,spec['properties'][name],path+'.'+name)
    elif isinstance(value,list):
        for i,item in enumerate(value): validate(item,spec['items'],f'{path}[{i}]')

def evidence_errors(entity,chunk):
    errors=[];local={p['id']:p for p in chunk};evidence=entity['evidence']
    if not entity['spoken_name'].strip() or not evidence: errors.append('Missing spoken name/evidence')
    for e in evidence:
        if e['passage_id'] not in local or not e['quote'].strip() or e['quote'] not in local[e['passage_id']]['text']: errors.append('Evidence quote/ID not present verbatim in this chunk')
    for form in entity['observed_forms']:
        if not form.strip() or not any(form in e['quote'] for e in evidence): errors.append('Observed form not in supporting quotes')
    if entity['kind'] not in ['paper','article'] and not entity['observed_forms']: errors.append('Name has no literal observed form')
    proposal=entity['normalized_name']
    # Canonical-name proposals never become accepted names automatically. Missing
    # rationale is a review warning, not a reason to discard valid source evidence.
    pub=entity['publication']
    if pub is not None:
        if entity['kind'] not in ['paper','article']: errors.append('Publication metadata on a non-reference')
        for e in pub['metadata_evidence']:
            if e['passage_id'] not in local or not e['quote'].strip() or e['quote'] not in local[e['passage_id']]['text']: errors.append('Metadata quote/ID not present verbatim')
        for field in ['title','authors','year','journal_or_publisher','doi','url']:
            values=pub[field] if isinstance(pub[field],list) else [] if pub[field] is None else [str(pub[field])]
            quotes=[e['quote'] for e in pub['metadata_evidence'] if e['field']==field]
            if values and not quotes: errors.append('Missing metadata evidence for '+field)
            if any(not any(str(v) in quote for quote in quotes) for v in values): errors.append('Metadata value not literally supported: '+field)
    return sorted(set(errors))

uncertain_path=outputs/'unresolved-usage.json'
uncertain=read_json(uncertain_path)['reserved_usd'] if uncertain_path.exists() else 0
if not isinstance(uncertain,(int,float)) or not 0<=uncertain<=args.max_usd:
    raise SystemExit('Invalid unresolved request cost reserve.')
responses=[];spent=0;rejected=[];accepted=[]
for i,chunk in enumerate(chunks,1):
    chunk_id=f'{i:03}';payload=dict(model=args.model,store=False,reasoning={'effort':'medium'},max_output_tokens=args.max_output_tokens,
        instructions=prompt,input=json.dumps(dict(episode_guid=guid,episode_title=source['episode_title'],passages=[dict(id=p['id'],text=p['text']) for p in chunk]),ensure_ascii=False),
        text={'format':{'type':'json_schema','name':'podcast_index','strict':True,'schema':schema}})
    request_path=outputs/'requests'/f'{chunk_id}.json';response_path=outputs/'responses'/f'{chunk_id}.json'
    immutable(request_path,payload)
    if response_path.exists(): response=read_json(response_path);print(f'Chunk {i}/{len(chunks)}: using saved response.',flush=True)
    else:
        if args.reprocess_only: raise SystemExit('Missing cached response; reprocessing never makes API requests.')
        # Byte count is a conservative text-token bound; no speculative retry.
        worst_input=len(json.dumps(payload,ensure_ascii=False).encode())
        reserve=(worst_input*rates['input_per_million']*1.25+args.max_output_tokens*rates['output_per_million'])/1000000
        if spent+uncertain+reserve>args.max_usd: raise SystemExit(f'Next request could exceed ${args.max_usd:.2f} trial ceiling including unresolved usage; ${spent:.4f} recorded so far. No request made.')
        print(f'Chunk {i}/{len(chunks)}: requesting passages {chunk[0]["id"]}–{chunk[-1]["id"]} (ceiling ${reserve:.2f}).',flush=True)
        response,request_id=request_json('responses',payload);response['_trial_request_id']=request_id
        write_json(response_path,response)
    usage=response.get('usage') or {};calculated=cost(usage);spent+=calculated
    responses.append(dict(chunk=i,response_id=response.get('id'),request_id=response.get('_trial_request_id'),model=response.get('model'),status=response.get('status'),usage=usage,calculated_usd=calculated))
    write_json(outputs/'usage.json',dict(currency='USD',requests=responses,calculated_total_usd=spent,unresolved_cost_reserve_usd=uncertain,pricing=pricing,
        cache_write_per_million=rates['input_per_million']*1.25,billing_note='Calculation from API-reported tokens at recorded standard rates, including default 30m cache-write tokens at 1.25x input rate; not an invoice. Output includes reasoning tokens. Transport failures may have unrecorded charges.'))
    if response.get('status')!='completed': raise SystemExit('Incomplete API response retained with usage; no automatic retry.')
    texts=[c['text'] for item in response.get('output',[]) if item.get('type')=='message' for c in item.get('content',[]) if c.get('type')=='output_text']
    if not texts: raise SystemExit('API refused or returned no extraction text; response retained.')
    parsed=json.loads(''.join(texts));validate(parsed,schema)
    for entity in parsed['entries']:
        errors=evidence_errors(entity,chunk)
        if errors: rejected.append(dict(chunk=i,errors=errors,proposal=entity));continue
        accepted.append(dict(chunk=i,proposal=entity))
    write_json(outputs/'validation.json',dict(accepted_chunk_entries=len(accepted),rejected_chunk_entries=len(rejected),rejected=rejected,
        note='Evidence validation verifies literal wording/IDs and metadata provenance, not scientific identity.'))

merged={}
for item in accepted:
    e=item['proposal'];proposed=e['normalized_name']
    placeholder=e['kind'] in ['paper','article'] and proposed in ['Untitled paper','Untitled article']
    normalization_warning=bool(proposed and canonical(proposed)!=canonical(e['spoken_name']) and not e['normalization_reason'] and not placeholder)
    name=e['spoken_name'] if normalization_warning else proposed or e['spoken_name']
    identity=[e['kind'],canonical(e['subtype']),canonical(name)]
    if e['kind'] in ['paper','article']:
        if e['publication'] and e['publication']['doi']: identity.append(e['publication']['doi'])
        elif e['publication'] and e['publication']['title']: identity.append(canonical(e['publication']['title']))
        else: identity.extend([str(min(p['passage_id'] for p in e['evidence'])),canonical(e['qualifier'])])
    key_id=sha(json.dumps(identity).encode())[:20]
    if key_id not in merged:
        merged[key_id]=dict(id=key_id,kind=e['kind'],subtype=e['subtype'],name=name,spoken_names=[],observed_forms=[],qualifiers=[],normalization_proposals=[],normalization_warnings=[],confidence=e['confidence'],review='suggested',publication_proposals=[],occurrences=[])
    target=merged[key_id]
    for field,value in [('spoken_names',e['spoken_name']),('qualifiers',e['qualifier'])]:
        if value not in target[field]: target[field].append(value)
    for form in e['observed_forms']:
        if form not in target['observed_forms']: target['observed_forms'].append(form)
    if normalization_warning:
        warning=dict(proposed_name=proposed,spoken_name=e['spoken_name'],reason='Model supplied no normalization rationale; retain spoken name pending review.')
        if warning not in target['normalization_warnings']: target['normalization_warnings'].append(warning)
    if e['normalization_reason'] and e['normalization_reason'] not in target['normalization_proposals']: target['normalization_proposals'].append(e['normalization_reason'])
    if e['publication'] and e['publication'] not in target['publication_proposals']: target['publication_proposals'].append(e['publication'])
    for evidence in e['evidence']:
        cue=by_id[evidence['passage_id']]
        occurrence=dict(passage_id=cue['id'],quote=evidence['quote'],audio_start_ms=cue['audio_start_ms'],audio_time=stamp(cue['audio_start_ms']),episode_guid=guid,audio_identity=source['audio_identity'],edition=source['edition'])
        if not any(o['passage_id']==cue['id'] and o['quote']==evidence['quote'] for o in target['occurrences']): target['occurrences'].append(occurrence)
entities=sorted(merged.values(),key=lambda e:(e['kind'],e['name'].casefold()))
for e in entities: e['occurrences'].sort(key=lambda o:o['passage_id'])
write_json(outputs/'proposed-index.json',dict(schema_version=1,source_sha256=config['source_sha256'],episode_guid=guid,review='unaccepted API proposals',entries=entities))
lines=['# Karoo contextual index — API proposals','',f'Model: {args.model}. {len(entities)} consolidated entries. Calculated API cost: US${spent:.4f}.',
    '', 'All entries require review. Quotes and passage IDs were checked by code; identities and spelling proposals are not thereby verified. No accepted app index was changed.','']
for kind in ['fossil','place','paper','article','author']:
    lines+=['## '+kind.title(), '']
    for e in [row for row in entities if row['kind']==kind]:
        lines += [f'### {e["name"]} — {e["subtype"]}', '', 'Spoken forms: '+', '.join(e['spoken_names']), '']
        for reason in e['normalization_proposals']: lines += ['Normalization proposal: '+reason,'']
        for warning in e['normalization_warnings']: lines += ['Unreviewed normalization: '+warning['proposed_name']+'. '+warning['reason'],'']
        for o in e['occurrences']: lines += [f'- Passage {o["passage_id"]} · {o["audio_time"]}: {o["quote"]}']
        lines+=['']
(outputs/'INDEX_REVIEW.md').write_text('\n'.join(lines)+'\n')
sample=read_json(outputs/'manual-sample.json') if (outputs/'manual-sample.json').exists() else {'required':[]};comparisons=[]
for expected in sample['required']:
    hits=[e for e in entities if e['kind']==expected['kind'] and any(canonical(name) in {canonical(e['name']),*[canonical(s) for s in e['spoken_names']],*[canonical(s) for s in e['observed_forms']]} for name in expected['acceptable_names']) and any(o['passage_id'] in expected['passage_ids'] for o in e['occurrences'])]
    comparisons.append(dict(expected=expected,candidate_ids=[e['id'] for e in hits],recovered=bool(hits)))
write_json(outputs/'sample-comparison.json',dict(required_cases=len(comparisons),recovered_cases=sum(c['recovered'] for c in comparisons),cases=comparisons,
    note='Automatic name/context comparison against prewritten manual sample; review candidates for false positives and incorrect normalization separately.'))
print(f'Completed: {len(entities)} consolidated proposals, {len(rejected)} evidence-rejected chunk entries, calculated US${spent:.4f}.',flush=True)
print(f'Review: {outputs/"INDEX_REVIEW.md"}',flush=True)
PY_TRIAL

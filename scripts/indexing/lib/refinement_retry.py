"""Stage and activate a refinement-only revision without changing media editions."""
from pathlib import Path
import copy, fcntl, hashlib, json, os


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def atomic(path, value):
    pending = path.with_name(path.name + '.pending')
    with pending.open('w') as f:
        json.dump(value, f, indent=2, ensure_ascii=False); f.write('\n'); f.flush(); os.fsync(f.fileno())
    pending.replace(path)


def stage_retry(project, guid, run_id):
    project = Path(project).resolve(); root = project / 'work/episode-preparation'
    library = root / 'library.json'; entry = load(library).get(guid)
    if not entry:
        raise ValueError('Refinement retry requires an existing worker-prepared episode.')
    package = (project / entry['package']).resolve()
    source = (project / entry['index_directory']).resolve() if entry.get('index_directory') else package/'indexing'
    if not package.is_relative_to(root/'packages') or not source.is_relative_to(root):
        raise ValueError('Unsafe active package/index path.')
    manifest = load(package/'episode.json'); summary = load(source/'summary.json')
    baseline = (package/manifest['transcript']['reviewed_file']).resolve()
    if not baseline.is_relative_to(package):
        raise ValueError('Unsafe transcript path.')
    if (manifest['episode_guid'] != guid or summary['episode_guid'] != guid or summary['edition'] != entry['edition']
            or summary['index_sha256'] != digest(source/'index.json') or summary['baseline_sha256'] != digest(baseline)):
        raise ValueError('Active index, episode, edition or transcript hash mismatch.')
    staged = root/'index-revisions'/entry['key']/run_id
    staged.mkdir(parents=True,exist_ok=False)
    hashes = {}
    for name in ['index.json','summary.json']:
        data = (source/name).read_bytes(); hashes[str(source/name)] = hashlib.sha256(data).hexdigest()
        (staged/name).write_bytes(data)
    hashes[str(package/'episode.json')] = digest(package/'episode.json')
    hashes[str(baseline)] = digest(baseline)
    return dict(project=str(project),guid=guid,run_id=run_id,entry=copy.deepcopy(entry),package=str(package),
                source=str(source),staged=str(staged),hashes=hashes,edition=entry['edition'])


def activate_retry(context):
    project = Path(context['project']); library = project/'work/episode-preparation/library.json'
    staged = Path(context['staged']); summary = load(staged/'summary.json')
    if (summary['episode_guid'] != context['guid'] or summary['edition'] != context['edition']
            or summary['index_sha256'] != digest(staged/'index.json')
            or summary.get('refinement',{}).get('state') not in ('completed','partial')):
        raise ValueError('Refined index failed final validation; active edition retained.')
    with library.with_suffix('.json.lock').open('a') as lock:
        fcntl.lockf(lock,fcntl.LOCK_EX)
        doc = load(library)
        if doc.get(context['guid']) != context['entry'] or any(digest(Path(p)) != h for p,h in context['hashes'].items()):
            raise ValueError('Active edition/index changed during refinement; reviewed result retained without activation.')
        entry = dict(context['entry'],index_directory=str(staged.relative_to(project)),index_sha256=summary['index_sha256'])
        doc[context['guid']] = entry; atomic(library,doc)
    return summary

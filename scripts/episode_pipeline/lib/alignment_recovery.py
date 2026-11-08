"""Checkpointed alignment calls and conservative passage-boundary recovery."""
from copy import deepcopy
import hashlib
import json
import math
import numbers
import os
from pathlib import Path
import uuid

MAX_DISPLAY_OVERLAP_MS = 500


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     allow_nan=False).encode()).hexdigest()


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with pending.open('w') as file:
            json.dump(value, file, indent=2, ensure_ascii=False, allow_nan=False)
            file.write('\n')
            file.flush()
            os.fsync(file.fileno())
        pending.replace(path)
    finally:
        pending.unlink(missing_ok=True)


def normalize_acoustic_result(value, path='result'):
    """Convert real numeric scalars (including NumPy) at the library boundary."""
    if value is None or isinstance(value, (str, bool)):
        return value
    if isinstance(value, numbers.Integral):
        return int(value)
    if isinstance(value, numbers.Real):
        number = float(value)
        if not math.isfinite(number):
            raise ValueError(f'Non-finite acoustic value at {path}: {number!r}.')
        return number
    if isinstance(value, dict):
        return {key: normalize_acoustic_result(item, f'{path}.{key}') for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize_acoustic_result(item, f'{path}[{index}]') for index, item in enumerate(value)]
    raise ValueError(f'Unsupported acoustic value at {path}: {type(value).__module__}.{type(value).__name__}.')


def diagnostic_value(value):
    """JSON-safe evidence even when a model emits NaN or an unsupported scalar."""
    if value is None or isinstance(value, (str, bool)):
        return value
    if isinstance(value, numbers.Integral):
        return int(value)
    if isinstance(value, numbers.Real):
        number = float(value)
        return number if math.isfinite(number) else dict(non_finite_number=repr(number),
            python_type=type(value).__module__ + '.' + type(value).__name__)
    if isinstance(value, dict):
        return {str(key): diagnostic_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [diagnostic_value(item) for item in value]
    return dict(unsupported_value=repr(value)[:200],
                python_type=type(value).__module__ + '.' + type(value).__name__)


def capture_acoustic_result(cache, request, result, passages, outputs):
    """Persist raw evidence, then normalize and validate the library boundary."""
    outputs = Path(outputs)
    raw_file = cache.folder / 'raw' / (fingerprint(request) + '.json')
    atomic_json(raw_file, dict(request=request, result=diagnostic_value(result)))
    try:
        normalized = normalize_acoustic_result(result)
        words = [word for segment in normalized['segments'] for word in segment.get('words', [])]
        word_bounds(words)
    except (ValueError, TypeError, KeyError) as error:
        failure = outputs / 'alignment-failure.json'
        atomic_json(failure, dict(state='failed', reason=str(error),
            passage_ids=[cue['id'] for cue in passages], request=request,
            raw_result_file=str(raw_file.relative_to(outputs)), passages=passages))
        atomic_json(outputs / 'alignment-validation.json', dict(state='failed',
            diagnostic=failure.name, raw_result_file=str(raw_file.relative_to(outputs))))
        raise ValueError(f"Acoustic output validation failed for passages {passages[0]['id']}–{passages[-1]['id']}: {error} Raw result saved: {raw_file.relative_to(outputs)}") from error
    return normalized


class AlignmentCache:
    """Content-addressed, checksummed calls; stale namespaces never mix."""
    def __init__(self, outputs, identity):
        self.identity = identity
        self.namespace = fingerprint(identity)
        self.folder = Path(outputs) / 'alignment-cache' / self.namespace
        atomic_json(self.folder / 'identity.json', identity)
        self.hits = 0
        self.misses = 0

    def call(self, request, compute):
        path = self.folder / (fingerprint(request) + '.json')
        if path.exists():
            try:
                saved = json.loads(path.read_text())
                if (saved['namespace'] != self.namespace or saved['request'] != request
                        or saved['sha256'] != fingerprint(saved['result'])):
                    raise ValueError('identity/checksum mismatch')
                result = saved['result']
            except (KeyError, ValueError, TypeError) as error:
                raise ValueError(f'Alignment checkpoint is invalid: {path}; inspect before retrying.') from error
            self.hits += 1
            return result, True
        result = compute()
        atomic_json(path, dict(namespace=self.namespace, request=request,
                               result=result, sha256=fingerprint(result)))
        self.misses += 1
        return result, False


def word_bounds(words):
    timed = [w for w in words if 'start' in w and 'end' in w]
    if not timed:
        return None
    for index, word in enumerate(timed):
        for field in ('start', 'end'):
            value = word[field]
            if isinstance(value, bool) or not isinstance(value, numbers.Real) or not math.isfinite(value):
                raise ValueError(f"Malformed acoustic timing at word {index + 1} {word.get('word', '')!r}: {field}={value!r} ({type(value).__module__}.{type(value).__name__}).")
        if word['start'] > word['end']:
            raise ValueError(f"Reversed acoustic timing at word {index + 1} {word.get('word', '')!r}: start={word['start']!r}, end={word['end']!r}.")
    return round(min(w['start'] for w in timed) * 1000), round(max(w['end'] for w in timed) * 1000)


def conflict_indices(cues, aligned, duration_ms):
    spans = [word_bounds(aligned[c['id']]) or (c['start_ms'], c['end_ms']) for c in cues]
    conflicts = set()
    for index, (start, end) in enumerate(spans):
        if not 0 <= start < end <= duration_ms:
            conflicts.add(index)
        if index + 1 < len(spans) and end > spans[index + 1][0]:
            conflicts.update((index, index + 1))
    return sorted(conflicts)


def conflict_windows(indices, size, padding):
    windows = []
    for index in indices:
        first, last = max(0, index - padding), min(size - 1, index + padding)
        if windows and first <= windows[-1][1] + 1:
            windows[-1] = (windows[-1][0], max(last, windows[-1][1]))
        else:
            windows.append((first, last))
    return windows


def recover_groups(cues, aligned, duration_ms, align_range, outputs):
    """Replace whole connected windows, preserving one shared acoustic mapping."""
    outputs = Path(outputs)
    repairs = []
    for iteration, padding in enumerate((2, 4, 8), 1):
        indices = conflict_indices(cues, aligned, duration_ms)
        if not indices:
            break
        atomic_json(outputs / f'alignment-conflicts-pass-{iteration}.json', dict(
            passage_ids=[cues[i]['id'] for i in indices],
            passages=[dict(cues[i], words=aligned[cues[i]['id']]) for i in indices]))
        windows = conflict_windows(indices, len(cues), padding)
        for first, last in windows:
            # Do not turn one failure into an unbounded full-episode inference.
            if last - first + 1 > 80 or cues[last]['end_ms'] - cues[first]['start_ms'] > 180000:
                repairs.append(dict(iteration=iteration, first_id=cues[first]['id'],
                                    last_id=cues[last]['id'], skipped='Window exceeds bounded recovery policy.'))
                continue
            result = align_range(first, last)
            # Adopt every passage in this context window, not just the pair.
            for cue in cues[first:last + 1]:
                aligned[cue['id']] = result[cue['id']]
            repairs.append(dict(iteration=iteration, first_id=cues[first]['id'], last_id=cues[last]['id']))
            atomic_json(outputs / 'alignment-recovery-progress.json', dict(
                repairs=repairs, passages=[dict(c, words=aligned[c['id']]) for c in cues]))
        print(f'Boundary pass {iteration}: jointly realigned {len(windows)} connected groups', flush=True)
    return repairs


def reconcile_display(records, duration_ms, maximum_overlap_ms=MAX_DISPLAY_OVERLAP_MS):
    """Reconcile only small, ordered overlaps; raw acoustic words stay unchanged.

    Work on a copy so failure diagnostics contain the original candidate timings.
    """
    result = deepcopy(records)
    boundaries, problems = [], []
    for row in result:
        if not 0 <= row['start_ms'] < row['end_ms'] <= duration_ms:
            problems.append(dict(passage_ids=[row['id']], reason='Non-positive or out-of-bounds passage timing.'))
    if problems:
        return result, boundaries, problems
    for a, b in zip(result, result[1:]):
        overlap = a['end_ms'] - b['start_ms']
        if overlap <= 0:
            continue
        # A contained/reversed passage is an acoustic conflict, not a tiny display overlap.
        ordered = a['start_ms'] <= b['start_ms'] and a['end_ms'] <= b['end_ms']
        lower = max(a['start_ms'] + 1, b['start_ms'])
        upper = min(a['end_ms'], b['end_ms'] - 1)
        if not ordered or overlap > maximum_overlap_ms or lower > upper:
            problems.append(dict(passage_ids=[a['id'], b['id']], reason='Unresolved acoustic overlap or non-monotonic ordering.',
                                 overlap_ms=overlap, left_start_ms=a['start_ms'], left_end_ms=a['end_ms'],
                                 right_start_ms=b['start_ms'], right_end_ms=b['end_ms']))
            continue
        boundary = max(lower, min(upper, round((a['end_ms'] + b['start_ms']) / 2)))
        boundaries.append(dict(left=a['id'], right=b['id'], raw_left_end_ms=a['end_ms'],
                               raw_right_start_ms=b['start_ms'], display_boundary_ms=boundary))
        a['end_ms'] = b['start_ms'] = boundary
        for row in (a, b):
            row['review_flags'].append('Small shared display boundary reconciles overlapping word timings; listening review recommended.')
    if not problems:
        previous = 0
        for row in result:
            if not previous <= row['start_ms'] < row['end_ms'] <= duration_ms:
                problems.append(dict(passage_ids=[row['id']], reason='Final positive ordered timing validation failed.'))
            previous = row['end_ms']
    return result, boundaries, problems


def select_cached_path(cues, aligned, duration_ms, cache, outputs):
    """Select a consistent sequence from exact, verified acoustic alternatives.

    Prefer the fewest changed passages, then higher mean word scores. This is a
    constrained choice among model results, not interpolation or a confidence
    guarantee. A complete path must pass the existing display validator too.
    """
    options = {cue['id']: [] for cue in cues}
    seen = {cue['id']: set() for cue in cues}
    by_id = {cue['id']: cue for cue in cues}

    def add(cue_id, words, source):
        span = word_bounds(words)
        if span is None or not 0 <= span[0] < span[1] <= duration_ms:
            return
        key = fingerprint(words)
        if key in seen[cue_id]:
            return
        seen[cue_id].add(key)
        scores = [w['score'] for w in words if isinstance(w.get('score'), numbers.Real)
                  and math.isfinite(w['score'])]
        score = sum(scores) / len(scores) if scores else 0
        options[cue_id].append(dict(words=words, span=span, source=source,
                                    changed=source != 'current', score=score))

    for cue in cues:
        add(cue['id'], aligned[cue['id']], 'current')
    for path in sorted(cache.folder.glob('*.json')):
        if path.name == 'identity.json':
            continue
        saved = json.loads(path.read_text())
        request = saved.get('request', {})
        if (saved.get('namespace') != cache.namespace or path.stem != fingerprint(request)
                or saved.get('sha256') != fingerprint(saved.get('result'))):
            raise ValueError(f'Alignment checkpoint is invalid: {path}; cannot select acoustic alternatives.')
        passages = request.get('passages', [])
        if not passages or any(c['id'] not in by_id or c['text'] != by_id[c['id']]['text'] for c in passages):
            raise ValueError(f'Alignment checkpoint passage evidence mismatch: {path}.')
        words = [w for segment in saved['result']['segments'] for w in segment.get('words', [])]
        expected = [word for cue in passages for word in cue['text'].split()]
        if [w.get('word') for w in words] != expected:
            raise ValueError(f'Alignment checkpoint word mapping mismatch: {path}.')
        offset = 0
        for cue in passages:
            count = len(cue['text'].split())
            add(cue['id'], words[offset:offset + count], path.name)
            offset += count

    def compatible(left, right):
        a, b = left['span'], right['span']
        if a[1] <= b[0]:
            return True
        return (a[0] <= b[0] and a[1] <= b[1]
                and a[1] - b[0] <= MAX_DISPLAY_OVERLAP_MS
                and max(a[0] + 1, b[0]) <= min(a[1], b[1] - 1))

    layers = []
    for index, cue in enumerate(cues):
        layer = []
        choices = options[cue['id']]
        for choice in choices:
            increment = (int(choice['changed']), -choice['score'])
            if index == 0:
                layer.append((increment, None))
                continue
            previous_choices = options[cues[index - 1]['id']]
            feasible = []
            for prior_index, prior in enumerate(layers[-1]):
                if prior is not None and compatible(previous_choices[prior_index], choice):
                    feasible.append(((prior[0][0] + increment[0], prior[0][1] + increment[1]), prior_index))
            layer.append(min(feasible, key=lambda item: item[0]) if feasible else None)
        layers.append(layer)
        if not any(state is not None for state in layer):
            atomic_json(Path(outputs) / 'alignment-alternative-selection.json', dict(
                state='no_complete_path', cache_namespace=cache.namespace, blocked_at_passage=cue['id']))
            return False

    if not cues:
        return False
    last = min((i for i, state in enumerate(layers[-1]) if state is not None),
               key=lambda i: layers[-1][i][0])
    selected = []
    for index in range(len(cues) - 1, -1, -1):
        selected.append(options[cues[index]['id']][last])
        last = layers[index][last][1]
    selected.reverse()
    candidate_records = [dict(id=cue['id'], start_ms=choice['span'][0], end_ms=choice['span'][1],
                              words=choice['words'], review_flags=[])
                         for cue, choice in zip(cues, selected)]
    _, _, problems = reconcile_display(candidate_records, duration_ms)
    if problems:
        atomic_json(Path(outputs) / 'alignment-alternative-selection.json', dict(
            state='display_validation_failed', problems=problems, cache_namespace=cache.namespace))
        return False
    changes = []
    for cue, choice in zip(cues, selected):
        if choice['changed']:
            changes.append(dict(passage_id=cue['id'], previous_span=word_bounds(aligned[cue['id']]),
                selected_span=choice['span'], cached_call=choice['source']))
        aligned[cue['id']] = deepcopy(choice['words'])
    atomic_json(Path(outputs) / 'alignment-alternative-selection.json', dict(
        state='selected', cache_namespace=cache.namespace, changes=changes,
        policy='Fewest changed passages, then highest aggregate mean word score; complete ordered path required.'))
    return True

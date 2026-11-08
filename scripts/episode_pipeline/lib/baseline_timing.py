"""Conservative provisional timing repair before acoustic alignment."""

def prepare_segments(rows, duration_ms, tolerance_ms=1000):
    if not rows or type(duration_ms) is not int or duration_ms <= 0:
        raise ValueError('Baseline failed: missing passages or invalid audio duration.')
    segments, originals = [], []
    previous_end = 0
    for number, row in enumerate(rows, 1):
        text = row.get('text', '').strip()
        offsets = row.get('offsets', {})
        start, end = offsets.get('from'), offsets.get('to')
        if not text or type(start) is not int or type(end) is not int:
            raise ValueError(f'Baseline failed: passage {number} has empty text or non-integer timestamps; inspect raw-transcript.json.')
        if start < 0 or end < start or start > duration_ms or end > duration_ms + tolerance_ms:
            raise ValueError(f'Baseline failed: passage {number} has reversed/out-of-bounds timing {start}–{end} ms (audio {duration_ms} ms). Raw text retained.')
        originals.append((start, end))
        start = max(start, previous_end)
        end = max(min(end, duration_ms), start + 1)
        segments.append(dict(id=number, start_ms=start, end_ms=end, text=text))
        previous_end = end
    # A zero-length final cue needs room on its left, rather than beyond audio.
    boundary = duration_ms
    for row in reversed(segments):
        row['end_ms'] = min(row['end_ms'], boundary)
        row['start_ms'] = min(row['start_ms'], row['end_ms'] - 1)
        boundary = row['start_ms']
    repairs = []
    for row, (start, end) in zip(segments, originals):
        if row['start_ms'] < 0 or max(abs(row['start_ms'] - start), abs(row['end_ms'] - end)) > tolerance_ms:
            raise ValueError(f"Baseline failed: passage {row['id']} needs more than {tolerance_ms} ms of provisional timing repair; manual inspection required. Raw transcript retained.")
        if (start, end) != (row['start_ms'], row['end_ms']):
            repairs.append(dict(passage_id=row['id'], original_start_ms=start, original_end_ms=end,
                provisional_start_ms=row['start_ms'], provisional_end_ms=row['end_ms'],
                reason='Provisional positive ordered timing for acoustic alignment; not an audio-verified correction.'))
    return segments, repairs


def refinement_failure_summary(review_dir):
    """Do not imply an API request occurred without a request marker."""
    import json
    usage_path, marker_path = review_dir/'usage.json', review_dir/'request-started.json'
    usage = json.loads(usage_path.read_text()) if usage_path.exists() else {}
    if not marker_path.exists():
        return dict(state='not_reached', warning='ChatGPT refinement was not reached. No refinement request was started by this run.', cost_usd=0, possible_billable_request=False)
    try:
        marker = json.loads(marker_path.read_text())
    except json.JSONDecodeError:
        marker = dict(reserved_usd=.50)
    return dict(state='interrupted', warning='ChatGPT refinement started but did not finish. Inspect saved usage before an explicit retry.', cost_usd=usage.get('cost_usd'), reserved_usd=marker.get('reserved_usd'), possible_billable_request=True)

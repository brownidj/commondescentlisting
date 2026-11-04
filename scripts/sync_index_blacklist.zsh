#!/bin/zsh
# Explicit offline import of deletion decisions from a listener registry.
set -euo pipefail
blacklist_project="${0:A:h:h}"
exec "${EPISODE_PYTHON:-python3}" - "$blacklist_project" "$@" <<'PY_BLACKLIST'
from pathlib import Path
import argparse,json,sys
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'scripts/indexing/lib'))
from index_policy import merge_blacklist
parser=argparse.ArgumentParser(description='Record registry deletions for future indexing; no network calls.')
parser.add_argument('registry',type=Path)
a=parser.parse_args(sys.argv[2:])
print('Saved deletion records:',merge_blacklist(root,json.loads(a.registry.read_text())))
PY_BLACKLIST

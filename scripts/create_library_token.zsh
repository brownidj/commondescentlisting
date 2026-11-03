#!/bin/zsh
set -euo pipefail
(( $# == 1 )) || { print -u2 'Usage: scripts/create_library_token.zsh /path/to/read-token'; exit 2; }
python3 - "$1" <<'PY_TOKEN'
from pathlib import Path
import os,secrets,sys
path=Path(sys.argv[1]).expanduser();path.parent.mkdir(parents=True,exist_ok=True)
fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as stream:stream.write(secrets.token_urlsafe(32)+'\n')
print('Read token created. Existing tokens are never overwritten.')
PY_TOKEN

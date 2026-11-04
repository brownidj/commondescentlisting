#!/bin/zsh
# Explicit network operation: fetch pinned large-model weights for the comparison.
set -euo pipefail
cache_project="${0:A:h:h:h}"
export HF_HOME="${cache_project}/work/gliner-upgrade/model-cache"
export HF_HUB_OFFLINE=0
exec "${cache_project}/work/gliner-upgrade/venv/bin/python" -u - "$cache_project" <<'PY'
from pathlib import Path
from huggingface_hub import HfApi,snapshot_download
import json,sys
project=Path(sys.argv[1]);record=project/'work/gliner-upgrade/models.json'
# Reuse the first resolved encoder revision on subsequent downloads.
existing=json.loads(record.read_text()) if record.exists() else None
encoder='microsoft/deberta-v3-large'
revision=next((r['revision'] for r in existing['models'] if r['repo']==encoder),None) if existing else None
revision=revision or HfApi().model_info(encoder).sha
models=[('urchade/gliner_large-v2.1','abd49a1f1ebc12af1be84d06f6848221cf96dcad',['gliner_config.json','pytorch_model.bin']),
        (encoder,revision,['config.json','tokenizer_config.json','tokenizer.json','special_tokens_map.json','spm.model','vocab.txt','added_tokens.json'])]
record.parent.mkdir(parents=True,exist_ok=True)
# Record revisions before transfer so interrupted downloads resume reproducibly.
record.write_text(json.dumps(dict(models=[dict(repo=r,revision=c) for r,c,_ in models]),indent=2)+'\n')
for repo,commit,patterns in models:
    print('Downloading',repo,commit,flush=True)
    snapshot_download(repo,revision=commit,allow_patterns=patterns,max_workers=2)
    # GLiNER's legacy encoder name resolves revision 'main' when loading offline.
    # Bind that alias to the recorded commit in this isolated comparison cache.
    ref=project/'work/gliner-upgrade/model-cache/hub'/('models--'+repo.replace('/','--'))/'refs/main'
    ref.parent.mkdir(parents=True,exist_ok=True)
    ref.write_text(commit)
print('Comparison model cache ready; no index published.')
PY

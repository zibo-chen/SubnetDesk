import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
page_id, source_name, brief = sys.argv[1:4]
result = subprocess.run(['/Users/chenzibo/.codex/bin/materialize-latest-generated-image'], capture_output=True, text=True)
if result.returncode != 0:
    rollout = Path('/Users/chenzibo/.codex/sessions/2026/10/19/rollout-2026-10-19T22-08-20-01a1577e-f382-7f93-994c-da3d7d40e108.jsonl')
    completed = 0
    for line in rollout.open():
        item = json.loads(line)
        payload = item.get('payload', {})
        if item.get('type') == 'response_item' and payload.get('type') == 'image_generation_call' and payload.get('status') == 'completed':
            completed += 1
    print(f'Display helper: no native response item; rollout inspected ({completed} completed); using tool-returned artifact.')
    source = Path(source_name)
else:
    source = Path(result.stdout.strip())
catalog = json.loads((root / 'catalog.json').read_text())
page = next(p for p in catalog['pages'] if p['id'] == page_id)
with Image.open(source) as im:
    size = list(im.size)
    im.verify()
assert min(size) >= 300, size
target = root / page['platform'] / (page['slug'] + '.png')
if target.exists() and target.read_bytes() != source.read_bytes():
    shutil.copy2(target, target.with_suffix('.previous.png'))
shutil.copy2(source, target)
manifest_path = root / 'manifest.json'
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
record = dict(page, file=str(target.relative_to(root)), source=str(source), dimensions=size, sha256=hashlib.sha256(target.read_bytes()).hexdigest(), brief=brief)
manifest = [p for p in manifest if p['id'] != page_id] + [record]
manifest.sort(key=lambda p: p['id'])
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'id':page_id,'path':str(target),'dimensions':size,'completed':len(manifest)},ensure_ascii=False))

#!/usr/bin/env python3
"""Record the built preview and matching source; never package or alter an app."""
from pathlib import Path
from datetime import datetime
import hashlib,json,plistlib,subprocess,zipfile
root=Path(__file__).resolve().parent.parent
out=root/'outputs';app=out/'Bonsai.app'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
meta=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert meta['CFBundleName']=='Bonsai' and meta['LSMinimumSystemVersion']=='14.0'
assert subprocess.check_output(['lipo','-archs',str(app/'Contents/MacOS/Bonsai')],text=True).strip()=='arm64'
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
files=sorted(p for p in app.rglob('*') if p.is_file() and not p.is_symlink())
manifest=dict(bundle=app.name,version=meta['CFBundleShortVersionString'],build=meta['CFBundleVersion'],identifier=meta['CFBundleIdentifier'],files=[dict(path=p.relative_to(app).as_posix(),bytes=p.stat().st_size,sha256=sha(p)) for p in files])
(out/'Bonsai-App-Manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
source=out/f"Bonsai-{meta['CFBundleShortVersionString']}-Source.zip"
with zipfile.ZipFile(source) as archive:
 assert archive.testzip() is None
 source_entries=len(archive.infolist())
sizes=dict(measuredAt=datetime.now().astimezone().isoformat(),bundle=app.name,version=meta['CFBundleShortVersionString'],build=meta['CFBundleVersion'],architecture='arm64',fileBytes=sum(p.stat().st_size for p in files),allocatedBytes=int(subprocess.check_output(['du','-sk',str(app)],text=True).split()[0])*1024,executableSHA256=sha(app/'Contents/MacOS/Bonsai'),signature='local ad-hoc hardened runtime; library validation enabled; not Developer ID signed/notarized',sourceArchive=dict(name=source.name,bytes=source.stat().st_size,entries=source_entries,sha256=sha(source)),currentDMG='Not packaged; pending user evaluation')
(out/'Bonsai-Artifact-Sizes.json').write_text(json.dumps(sizes,indent=2)+'\n')
version=meta['CFBundleShortVersionString']
names=[f'Bonsai-{version}-Changes.md',f'Bonsai-{version}-Verification.md',f'Bonsai-{version}-Core-Tests.txt','Bonsai-3.6.9-Live-Sparkle-Verification.txt',f'Bonsai-{version}-Disk-Performance.json',f'Bonsai-{version}-Build.txt',f'Bonsai-{version}-Final-Build.txt',f'Bonsai-{version}-Swift-Test.txt','Bonsai-Update-Observed-Log.txt','Bonsai-3.6.8-Live-Audit.json','Bonsai-3.6.8-Frame-Rate.jsonl','Bonsai-App-Manifest.json','Bonsai-Artifact-Sizes.json','Bonsai-Test-Results.txt','Bonsai-Build-Results.txt','Bonsai-Bundle-Verification.txt','Bonsai-Tree-Verification.txt','Bonsai-Installed-Verification.txt','Bonsai-Source-Verification.txt','Bonsai-Store-Wrapper-Verification.json','Bonsai-Clean-Guard-Tests.txt','Bonsai-Bonsai-Optimize-Verification.txt','Bonsai-Optimize-Comparison.md','Bonsai-Optimize-CLI-Preview.txt','Software-Services-Results.txt','Software-State-Results.txt','Bonsai-Icon.png','Bonsai-Verification.md','Bonsai-Release-Notes.md','Verification.md','Release-Notes.md','Feature-Checklist.md','Privacy.md','Installation.md','Release-Process.md','Test-Guide.md','BonsaiVerify']
# Visual-only revisions need not rerun unrelated service/performance suites.
# Preserve existing evidence and include only actual versioned checks produced.
required=[f'Bonsai-{version}-Changes.md',f'Bonsai-{version}-Verification.md',f'Bonsai-{version}-Build.txt',f'Bonsai-{version}-Final-Build.txt']
assert all((out/name).is_file() for name in required)
names=[name for name in names if (out/name).is_file()]
for suffix in ['Appearance-Tests.txt','Preferences-Tests.txt','Clean-Guards.txt','Software-State.txt','Software-Services.txt','Background-Mapping.txt','Preview-Build.txt','Status-Hover.txt','Bundle-Verification.txt','Settings-Scroll.txt','Design-Tests.txt','Production-Design-Tests.txt','Developer-Boundary.txt','Developer-GUI.txt','Installed-Preserved.txt']:
 name=f'Bonsai-{version}-{suffix}'
 if (out/name).is_file() and name not in names:names.append(name)
targets=[app/'Contents/MacOS/Bonsai',source]+[out/name for name in names]
(out/'Bonsai-SHA256.txt').write_text(''.join(f'{sha(p)}  {p.relative_to(root).as_posix()}\n' for p in targets))
for line in (out/'Bonsai-SHA256.txt').read_text().splitlines():digest,name=line.split('  ',1);assert sha(root/name)==digest
print(json.dumps(sizes,indent=2))
print(f'PASS: {len(files)} bundle records, {len(targets)} verified deliverable checksums.')

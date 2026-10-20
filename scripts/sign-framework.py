"""Developer ID path only. Preserve Sparkle's existing helper entitlements."""
import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);identity=sys.argv[2]

# Sparkle's executable helpers, XPC services, app, then framework itself.
magic={b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xfe\xed\xfa\xcf'}
files=[]
for p in root.rglob('*'):
 if p.is_symlink() or not p.is_file():continue
 with p.open('rb') as f:head=f.read(4)
 if head in magic:files.append(p)
bundles=[p for p in root.rglob('*') if not p.is_symlink() and p.is_dir() and p.suffix in ['.app','.xpc']]
for p in sorted(files,key=lambda p:len(p.parts),reverse=True)+sorted(bundles,key=lambda p:len(p.parts),reverse=True)+[root]:
 subprocess.run(['codesign','--force','--options','runtime']+(['--timestamp'] if identity!='-' else [])+['--preserve-metadata=identifier,entitlements','--sign',identity,str(p)],check=True)

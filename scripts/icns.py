# Write standard PNG-based ICNS elements; avoids iconutil dependencies on IconServices.
from pathlib import Path
import struct, sys
folder=Path(sys.argv[1])
elements=[('icp4','icon_16x16.png'),('icp5','icon_32x32.png'),('icp6','icon_32x32@2x.png'),('ic07','icon_128x128.png'),('ic08','icon_256x256.png'),('ic09','icon_512x512.png'),('ic10','icon_512x512@2x.png'),('ic11','icon_16x16@2x.png'),('ic12','icon_32x32@2x.png'),('ic13','icon_128x128@2x.png'),('ic14','icon_256x256@2x.png')]
chunks=[]
for tag,name in elements:
    data=(folder/name).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n')
    chunks.append(tag.encode()+struct.pack('>I',len(data)+8)+data)
body=b''.join(chunks)
Path(sys.argv[2]).write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)

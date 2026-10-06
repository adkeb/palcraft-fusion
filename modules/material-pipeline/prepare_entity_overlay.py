"""Local-only overlay PNG variants. Public source packages must not include MC skins."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def f32(v):
    return struct.unpack("<f",struct.pack("<f",v))[0]


def overlay(progress=0,red=False):
    if not math.isfinite(progress)or not 0<=progress<=1:
        raise ValueError("white progress range")
    u=math.trunc(f32(f32(progress)*15))
    if red:return u,3,(255,0,0),178,"red"
    a=math.trunc(f32(f32(1-f32(f32(u/15)*.75))*255))
    return u,10,(255,255,255),a,f"white_{u:02d}"


def mix_rgba(raw,rgb,weight):
    if len(raw)%4 or not 0<=weight<=255:raise ValueError("RGBA/weight")
    out=bytearray(raw)
    for p in range(0,len(out),4):
        for c in range(3):
            # Closest RGBA8 representation of shader mix(overlay,base,alpha).
            out[p+c]=(raw[p+c]*weight+rgb[c]*(255-weight)+127)//255
    return bytes(out)


def prepare(root,output,skins):
    from PIL import Image
    root,output=Path(root),Path(output)
    if root.resolve()==output.resolve():raise ValueError("Never edit private frozen assets")
    output.mkdir(parents=True,exist_ok=True)
    records={}
    for resource,path in skins.items():
        image=Image.open(root/path).convert("RGBA")
        raw=image.tobytes()
        identity=hashlib.sha256(raw).hexdigest()[:24]
        variants={}
        for key,(color,weight)in {
            **{f"white_{u:02d}":(overlay(u/15)[2],overlay(u/15)[3])for u in range(16)},
            "red":((255,0,0),178),
        }.items():
            rgba=mix_rgba(raw,color,weight)
            destination=Path(identity)/(key+".png")
            full=output/destination;full.parent.mkdir(parents=True,exist_ok=True)
            Image.frombytes("RGBA",image.size,rgba).save(full)
            variants[key]=destination.as_posix()
        records[resource]=dict(source_path=path,source_sha256=hashlib.sha256(raw).hexdigest(),variants=variants,
                               uv="vanilla0..1",alpha_preserved=True)
    manifest=dict(version=1,skins=records,private_mc_resources=True,
                  source_modified=False,requires_no_wpo_masked_shader_probe=True)
    (output/"index.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return manifest


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("private_asset_root");parser.add_argument("private_output")
    parser.add_argument("skin_map",help="JSON resource -> relative skin PNG paths")
    a=parser.parse_args()
    result=prepare(a.private_asset_root,a.private_output,json.loads(Path(a.skin_map).read_text()))
    print(json.dumps(dict(skins=len(result["skins"]),local_only=True,shader_verified=False)))

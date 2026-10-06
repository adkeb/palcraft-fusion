"""Precompute MC26.3's quantized RGBA sprite interpolation into a separate private root."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def f32(value):
    return struct.unpack("<f",struct.pack("<f",value))[0]


def progress_quantum(subframe,duration):
    if not isinstance(subframe,int)or not isinstance(duration,int)or duration<=0 or not 0<=subframe<duration:
        raise ValueError("Invalid MC subframe/time")
    return math.trunc(f32(f32(f32(subframe)/f32(duration))*1000.0))


def mix_rgba(current,next_frame,q):
    if len(current)!=len(next_frame)or len(current)%4 or not 0<=q<=1000:
        raise ValueError("RGBA dimensions/quantum")
    # The real26.3 fragment shader mixes the whole vec4, including alpha.
    return bytes((a*(1000-q)+b*q+500)//1000 for a,b in zip(current,next_frame))


def plan(animation):
    frames=animation.get("frames")
    if not isinstance(frames,list)or not frames or len(frames)>4096:
        raise ValueError("Invalid frame sequence")
    duration=sum(f["time"]for f in frames)
    if duration<=0 or duration>16384:
        raise ValueError("Invalid animation duration")
    result=[]
    for i,frame in enumerate(frames):
        index,time=frame["index"],frame["time"]
        if not isinstance(index,int)or index<0 or not isinstance(time,int)or time<=0:
            raise ValueError("Invalid sprite index/time")
        following=frames[(i+1)%len(frames)]["index"]
        for subframe in range(time):
            q=progress_quantum(subframe,time)if animation.get("interpolate")else 0
            if index==following:q=0
            result.append((index,following,q))
    return result


def prepare_sprite(asset_root,output_root,sprite,pixel_root=None):
    from PIL import Image
    asset_root,output_root=Path(asset_root),Path(output_root)
    if asset_root.resolve()==output_root.resolve():
        raise ValueError("Derived texture tree must not replace the frozen assets")
    if ".."in sprite or sprite.startswith("/"):
        raise ValueError("Invalid sprite")
    resource=sprite if ":"in sprite else "minecraft:"+sprite
    relative=resource.replace(":","/",1)
    meta=json.loads((asset_root/"textures"/(relative+".json")).read_text())
    animation=meta.get("animation")
    if not isinstance(animation,dict)or not animation.get("interpolate"):
        raise ValueError("Only actual interpolated sprite metadata is accepted")
    directory=animation["frames_dir"]
    if ".."in directory or directory.startswith("/"):raise ValueError("Invalid frame directory")
    timeline=plan(animation)
    images={}
    for index in set(x for a,b,q in timeline for x in(a,b)):
        image=Image.open(asset_root/directory/f"{index:04d}.png").convert("RGBA")
        if not 0<image.width<=1024 or not 0<image.height<=1024:raise ValueError("Frame too large")
        images[index]=(image.size,image.tobytes())
    if len(set(size for size,data in images.values()))!=1:raise ValueError("Frame size mismatch")
    digest=hashlib.sha256(json.dumps(animation,sort_keys=True).encode())
    for index,(size,raw)in sorted(images.items()):digest.update(index.to_bytes(4,"little"));digest.update(raw)
    identity=digest.hexdigest()[:24]
    generated_directory="__palcraft_interpolation/"+identity+"/"
    cache={};sequence=[];pixels={}
    for a,b,q in timeline:
        key=(a,b,q)
        if key not in cache:
            number=len(cache);cache[key]=number
            raw=mix_rgba(images[a][1],images[b][1],q)
            relative_png=generated_directory+f"{number:04d}.png"
            destination=output_root/relative_png
            destination.parent.mkdir(parents=True,exist_ok=True)
            Image.frombytes("RGBA",images[a][0],raw).save(destination)
            if pixel_root:
                raw_path=relative_png+".rgba"
                full=Path(pixel_root)/raw_path;full.parent.mkdir(parents=True,exist_ok=True);full.write_bytes(raw)
                pixels[relative_png]=dict(path=raw_path,width=images[a][0][0],height=images[a][0][1],
                    sha256=hashlib.sha256(raw).hexdigest(),alpha="straight")
        sequence.append(dict(index=cache[key],time=1))
    return dict(source_sprite=resource,source_sha256=meta["source_sha256"],identity=identity,
        ticks_per_second=animation.get("ticks_per_second",20),source_duration_ticks=len(timeline),
        generated_frames=len(cache),animation=dict(frames=sequence,frames_dir=generated_directory,
            ticks_per_second=animation.get("ticks_per_second",20),interpolate=False),pixel_records=pixels,
        private_mc_resources=True,source_modified=False,rgba_all_channels_interpolated=True,
        temporal_quantization="MC26.3 float32(subframe/time)*1000 -> int, shader /1000")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("asset_root");p.add_argument("private_output");p.add_argument("sprites",nargs="+")
    p.add_argument("--pixel-root",help="Optional separate bridge/material-pixels-v1 directory for tint-aware playback")
    a=p.parse_args()
    root=Path(a.private_output);root.mkdir(parents=True,exist_ok=True)
    records={};pixels={}
    for sprite in a.sprites:
        r=prepare_sprite(a.asset_root,root,sprite,a.pixel_root)
        records[r["source_sprite"]]=r
        pixels.update(r.pop("pixel_records"))
    (root/"index.json").write_text(json.dumps(dict(version=1,sprites=records,private_mc_resources=True),indent=2)+"\n")
    if a.pixel_root:
        output=Path(a.pixel_root)/"interpolation-index.json"
        output.write_text(json.dumps(dict(version=1,source_root=Path(a.asset_root).name,textures=pixels),indent=2)+"\n")
    print(json.dumps(dict(sprites=len(records),frames=sum(r["generated_frames"]for r in records.values()),
        source_modified=False,shader_verified=False)))

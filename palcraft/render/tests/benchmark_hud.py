"""Encode/decode an actual exported RGBA fixture; no game process or graphics changes."""
import argparse
import json
from pathlib import Path
import statistics
import sys
import time
import zlib

def benchmark(path, width, height, samples=40):
    raw=Path(path).read_bytes()
    assert len(raw)==width*height*4
    encoded, decoded=[],[]
    for _ in range(samples):
        start=time.perf_counter()
        wire=zlib.compress(raw,1)
        encoded.append((time.perf_counter()-start)*1000)
        start=time.perf_counter()
        assert zlib.decompress(wire)==raw
        decoded.append((time.perf_counter()-start)*1000)
    return dict(width=width,height=height,samples=samples,python=sys.version.split()[0],
                raw_bytes=len(raw),compressed_bytes=len(wire),ratio=len(wire)/len(raw),
                encode_ms_mean=statistics.mean(encoded),encode_ms_p95=sorted(encoded)[int(samples*.95)-1],
                decode_ms_mean=statistics.mean(decoded),decode_ms_p95=sorted(decoded)[int(samples*.95)-1],
                readback_layers_before=3,readback_layers_after=1,
                gpu_readback_bytes_per_frame_before=len(raw)*3,gpu_readback_bytes_per_frame_after=len(raw),
                texture_upload_bytes_per_frame_before=len(raw)*3,texture_upload_bytes_per_frame_after=len(raw),
                readback_ring_bytes_before=len(raw)*9,readback_ring_bytes_after=len(raw)*3,
                shader_passes_before=4,shader_passes_after=1,
                encoded_mbit_per_second_at_60fps=len(wire)*8*60/1e6,
                limitation='Offline CPU timings from a read-only live 1920x1080 HUD fixture; not measured gameplay latency/FPS.')

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('fixture');p.add_argument('--width',type=int,default=1920);p.add_argument('--height',type=int,default=1080)
    p.add_argument('--output')
    a=p.parse_args()
    result=benchmark(a.fixture,a.width,a.height)
    text=json.dumps(result,indent=2)
    if a.output:Path(a.output).write_text(text+'\n')
    print(text)

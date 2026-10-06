from pathlib import Path
import zlib,time,json,statistics
raw=Path(__file__).with_name('live-hud.rgba').read_bytes()
results={}
for name,strategy in [('default',zlib.Z_DEFAULT_STRATEGY),('rle',zlib.Z_RLE),('huffman',zlib.Z_HUFFMAN_ONLY)]:
 samples=[]
 for _ in range(20):
  t=time.perf_counter()
  obj=zlib.compressobj(1,zlib.DEFLATED,15,8,strategy)
  wire=obj.compress(raw)+obj.flush()
  samples.append((time.perf_counter()-t)*1000)
  assert zlib.decompress(wire)==raw
 results[name]={'mean_ms':statistics.mean(samples),'p95_ms':sorted(samples)[18],'bytes':len(wire)}
print(json.dumps(results,indent=2))
Path(__file__).with_name('compression-strategies.json').write_text(json.dumps(results,indent=2))

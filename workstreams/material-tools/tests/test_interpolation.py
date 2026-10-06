"""Small exact-tick/state tests, including alpha interpolation; no game or real-asset batch."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from PIL import Image

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from prepare_interpolated_frames import plan,progress_quantum,mix_rgba,prepare_sprite


class InterpolationTests(unittest.TestCase):
    def test_actual_mc_1000_quantization(self):
        self.assertEqual(progress_quantum(1,3),333)
        self.assertEqual(progress_quantum(2,3),666)
        self.assertEqual(progress_quantum(5,6),833)
        with self.assertRaises(ValueError):progress_quantum(3,3)

    def test_shader_mixes_alpha_too(self):
        self.assertEqual(mix_rgba(bytes([0,255,128,0]),bytes([255,0,128,255]),500),bytes([128,128,128,128]))
        self.assertEqual(mix_rgba(bytes([0,255,0,0]),bytes([255,0,255,255]),333),bytes([85,170,85,85]))

    def test_nonsequential_repeated_frame_and_loop(self):
        animation=dict(interpolate=True,frames=[dict(index=16,time=3),dict(index=0,time=2),dict(index=16,time=1)])
        self.assertEqual(plan(animation),[(16,0,0),(16,0,333),(16,0,666),(0,16,0),(0,16,500),(16,16,0)])

    def test_preparation_keeps_source_immutable(self):
        with tempfile.TemporaryDirectory(dir=str(Path('work/minecraft-fusion/material-pipeline').resolve()))as tmp:
            root=Path(tmp);src=root/'source';output=root/'derived';pixels=root/'pixels'
            folder=src/'textures/minecraft/block/test.frames';folder.mkdir(parents=True)
            Image.new('RGBA',(1,1),(0,255,0,0)).save(folder/'0016.png')
            Image.new('RGBA',(1,1),(255,0,255,255)).save(folder/'0000.png')
            meta=src/'textures/minecraft/block/test.json'
            meta.write_text(json.dumps(dict(source_sha256='fixture-source',animation=dict(
                interpolate=True,frames_dir='textures/minecraft/block/test.frames/',ticks_per_second=20,
                frames=[dict(index=16,time=3),dict(index=0,time=2)]))))
            before={str(p.relative_to(src)):p.read_bytes()for p in src.rglob('*')if p.is_file()}
            result=prepare_sprite(src,output,'minecraft:block/test',pixels)
            self.assertEqual(result['source_duration_ticks'],5)
            self.assertEqual(len(result['animation']['frames']),5)
            phase=result['animation']['frames'][1]['index']
            image=Image.open(output/result['animation']['frames_dir']/f'{phase:04d}.png')
            self.assertEqual(image.getpixel((0,0)),(85,170,85,85))
            after={str(p.relative_to(src)):p.read_bytes()for p in src.rglob('*')if p.is_file()}
            self.assertEqual(before,after)
            self.assertFalse(result['animation']['interpolate'])
            self.assertEqual(result['source_sha256'],'fixture-source')
            self.assertTrue(result['pixel_records'])

    def test_invalid_duration_and_traversal(self):
        with self.assertRaises(ValueError):plan(dict(frames=[dict(index=0,time=0)]))
        with self.assertRaises(ValueError):plan(dict(frames=[]))
        with self.assertRaises(ValueError):mix_rgba(b'\0'*4,b'\0'*8,500)


if __name__=='__main__':unittest.main()

import zipfile
from pathlib import Path
root=Path(__file__).resolve().parent
jar=Path("D:/PalworldServer-LAN/PalCraft-Dev/mc/.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-clientOnly-7e9a32a5b8/26.3/minecraft-clientOnly-7e9a32a5b8-26.3.jar")
names=["assets/minecraft/shaders/core/animate_sprite_interpolate.fsh","assets/minecraft/shaders/core/animate_sprite.vsh","assets/minecraft/shaders/include/animation_sprite.glsl"]
with zipfile.ZipFile(jar)as z:
 for n in names:
  raw=z.read(n)
  (root/n.rsplit("/",1)[1]).write_bytes(raw)
  print(n)
  print(raw.decode())

using CUE4Parse.FileProvider;
using CUE4Parse.UE4.Versions;
using CUE4Parse.UE4.Assets.Exports.StaticMesh;
using CUE4Parse.MappingsProvider.Usmap;
using CUE4Parse.Compression;
using Newtonsoft.Json;
using CUE4Parse.UE4.Assets.Exports.Texture;
using CUE4Parse_Conversion.Textures;
using System.IO.Compression;
using System.Buffers.Binary;

if(args.Length < 4) throw new ArgumentException("pak-directory mappings.usmap asset-list.json output.json");
using var provider = new DefaultFileProvider(args[0], SearchOption.TopDirectoryOnly,
    new VersionContainer(EGame.GAME_Palworld), StringComparer.OrdinalIgnoreCase);
if(File.Exists(args[1])) provider.MappingsContainer = new FileUsmapTypeMappingsProvider(args[1]);
provider.Initialize();
provider.Mount();
Console.WriteLine($"Mounted {provider.Files.Count} files");
if(args.Length>4 && File.Exists(args[4])) OodleHelper.Initialize(args[4]);
if(args[2]=="--list-wood") {
 var files=provider.Files.Keys.Where(k=>k.Contains("Architecture_Wood",StringComparison.OrdinalIgnoreCase)&&k.EndsWith(".uasset",StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(k).StartsWith("SM_",StringComparison.OrdinalIgnoreCase)).ToArray();
 File.WriteAllText(args[3],JsonConvert.SerializeObject(files));Console.WriteLine($"Wood mesh assets: {files.Length}");return;
}
var paths = JsonConvert.DeserializeObject<string[]>(File.ReadAllText(args[2]))!;
var result = new Dictionary<string,object>();
foreach(var path in paths) {
 try {
  var mesh=provider.LoadPackageObject<UStaticMesh>(path);
  var lods = new List<object>();
  if(mesh.RenderData is not null) {
   for(int i=0;i<mesh.RenderData.LODs.Length;i++) {
    var lod=mesh.RenderData.LODs[i];
    var verts=lod.PositionVertexBuffer?.Verts;
    var indices=lod.IndexBuffer?.Buffer;
    if(verts is null || indices is null || verts.Length==0 || indices.Length==0)continue;
    var frame=lod.VertexBuffer!.UV;
    lods.Add(new {level=i,vertices=verts.Select(v=>new[]{v.X,v.Y,v.Z}).ToArray(),indices=indices,
       uv=frame.Select(v=>new[]{v.UV[0].U,v.UV[0].V}).ToArray(),
       normals=frame.Select(v=>v.Normal[2].Data).ToArray(),
       sections=lod.Sections.Select(s=>new {material=s.MaterialIndex,first=s.FirstIndex,count=s.NumTriangles*3}).ToArray()});
   }
  }
  result[path]=new {asset=path,lods=lods};
  Console.WriteLine($"{path}: {lods.Count} rendered LODs");
 } catch(Exception ex) {result[path]=new {asset=path,error=ex.ToString()};Console.WriteLine($"FAILED {path}: {ex.Message}");}
 File.WriteAllText(args[3],JsonConvert.SerializeObject(result));
}
if(args.Length>5 && File.Exists(args[5])) {
 var textures=JsonConvert.DeserializeObject<string[]>(File.ReadAllText(args[5]))!;
 var outputDir=Path.Combine(Path.GetDirectoryName(args[3])!,"game-textures");Directory.CreateDirectory(outputDir);
 var index=new Dictionary<string,object>();
 TextureDecoder.UseAssetRipperTextureDecoder=true;
 foreach(var path in textures) {
  try {
   var tex=provider.LoadPackageObject<UTexture2D>(path);
   var name=path.Split('/').Last().Split('.')[0];
   var full=tex.Decode()!;var preview=tex.Decode(512)!;
   Png.Write(full,Path.Combine(outputDir,name+".png"));
   Png.Write(preview,Path.Combine(outputDir,name+"-mip.png"));
   index[path]=new {asset=path,file=name+".png",preview=name+"-mip.png",width=full.Width,height=full.Height,pixel_format=full.PixelFormat.ToString(),preview_width=preview.Width,preview_height=preview.Height};
   Console.WriteLine($"Texture {name}: {full.Width}x{full.Height}, {full.PixelFormat}");
  }catch(Exception ex){index[path]=new {asset=path,error=ex.ToString()};Console.WriteLine($"Texture FAILED {path}: {ex.Message}");}
 }
 File.WriteAllText(Path.Combine(outputDir,"texture-index.json"),JsonConvert.SerializeObject(index));
}

static class Png {
 public static void Write(CTexture texture,string path) {
  int w=texture.Width,h=texture.Height;var row=new byte[w*4+1];var raw=new MemoryStream();
  bool bgra=texture.PixelFormat.ToString()=="PF_B8G8R8A8",gray=texture.PixelFormat.ToString()=="PF_G8";
  if(!bgra && !gray && texture.PixelFormat.ToString()!="PF_R8G8B8A8")throw new NotSupportedException(texture.PixelFormat.ToString());
  using(var zip=new ZLibStream(raw,CompressionLevel.Fastest,true)) {
   for(int y=0;y<h;y++) {
    for(int x=0;x<w;x++) {
     int a=1+x*4,i=(y*w+x)*(gray?1:4);var data=texture.Data;
     row[a]=data[i+(bgra?2:0)];row[a+1]=data[i+(gray?0:1)];row[a+2]=data[i+(gray?0:(bgra?0:2))];row[a+3]=gray?(byte)255:data[i+3];
    }zip.Write(row);
   }
  }
  using var f=File.Create(path);f.Write(new byte[]{137,80,78,71,13,10,26,10});
  var header=new byte[13];BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(0,4),w);BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4,4),h);header[8]=8;header[9]=6;
  Chunk(f,"IHDR",header);Chunk(f,"IDAT",raw.ToArray());Chunk(f,"IEND",Array.Empty<byte>());
 }
 static void Chunk(Stream s,string name,byte[] data) {
  var type=System.Text.Encoding.ASCII.GetBytes(name);var size=new byte[4];BinaryPrimitives.WriteInt32BigEndian(size,data.Length);s.Write(size);s.Write(type);s.Write(data);
  var crc=new System.IO.Hashing.Crc32();crc.Append(type);crc.Append(data);BinaryPrimitives.WriteUInt32BigEndian(size,crc.GetCurrentHashAsUInt32());s.Write(size);
 }
}

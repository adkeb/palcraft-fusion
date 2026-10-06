// Read only the existing Pal cooked Item/Food table and the Berries row. No game calls.
using CUE4Parse.FileProvider;
using CUE4Parse.UE4.Versions;
using CUE4Parse.MappingsProvider.Usmap;
using CUE4Parse.UE4.Assets.Exports.Engine;
using Newtonsoft.Json;
if(args.Length!=3)throw new ArgumentException("pak-directory mappings.usmap output.json");
using var p=new DefaultFileProvider(args[0],SearchOption.TopDirectoryOnly,new VersionContainer(EGame.GAME_Palworld),StringComparer.OrdinalIgnoreCase);
p.MappingsContainer=new FileUsmapTypeMappingsProvider(args[1]);p.ReadShaderMaps=false;p.Initialize();p.Mount();
var candidates=p.Files.Keys.Where(f=>f.EndsWith(".uasset",StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(f).StartsWith("DT_",StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(f).Contains("Item",StringComparison.OrdinalIgnoreCase)).OrderBy(f=>f,StringComparer.Ordinal).ToArray();
var food=candidates.Where(f=>Path.GetFileName(f).Equals("DT_ItemDataTable.uasset",StringComparison.OrdinalIgnoreCase)||Path.GetFileName(f).Equals("DT_ItemDataTable_Common.uasset",StringComparison.OrdinalIgnoreCase)).ToArray();
var rows=new List<object>();
foreach(var f in food.Take(4)){
 try{
  var leaf=Path.GetFileNameWithoutExtension(f);var t=p.LoadPackageObject<UDataTable>(f[..^7]+"."+leaf);
  var matches=t.RowMap.Where(kv=>kv.Key.Text.Equals("Berries",StringComparison.Ordinal)).ToArray();
  foreach(var kv in matches)rows.Add(new{asset=f,row=kv.Key.Text,row_struct=t.RowStructName,data=JsonConvert.DeserializeObject<object>(JsonConvert.SerializeObject(kv.Value))});
 }catch(Exception e){rows.Add(new{asset=f,error=e.Message});}
}
File.WriteAllText(args[2],JsonConvert.SerializeObject(new{schema=1,scope="existing installed cooked item tables / Berries row only",read_only=true,candidate_item_table_paths=candidates,targeted_food_tables=food,rows,game_calls=0,assets_examined=Math.Min(food.Length,4)},Formatting.Indented));
Console.WriteLine("Read bounded Food tables; Berries matches="+rows.Count+"; game calls=0");

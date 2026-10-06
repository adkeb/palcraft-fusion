// Enumerate existing cooked archive filenames only. No asset load or game calls.
using CUE4Parse.FileProvider;
using CUE4Parse.UE4.Versions;
using Newtonsoft.Json;
if (args.Length != 2) throw new ArgumentException("pak-directory output.json");
using var provider = new DefaultFileProvider(args[0], SearchOption.TopDirectoryOnly,
    new VersionContainer(EGame.GAME_Palworld), StringComparer.OrdinalIgnoreCase);
provider.ReadShaderMaps = false;
provider.Initialize();
provider.Mount();
var matches = provider.Files.Keys.Where(path =>
    path.Contains("ShaderArchive-",StringComparison.OrdinalIgnoreCase) ||
    path.Contains("GlobalShaderCache-",StringComparison.OrdinalIgnoreCase))
    .OrderBy(path => path, StringComparer.Ordinal).ToArray();
var parents = provider.Files.Keys.Where(path =>
    Path.GetFileName(path).Equals("DefaultSpriteMaterial.uasset",StringComparison.OrdinalIgnoreCase) ||
    Path.GetFileName(path).Equals("M_PalLit.uasset",StringComparison.OrdinalIgnoreCase))
    .OrderBy(path => path,StringComparer.Ordinal).ToArray();
File.WriteAllText(args[1],JsonConvert.SerializeObject(new {
    schema=1,scope="archive index filenames only",pak_directory=args[0],
    indexed_files=provider.Files.Count,shader_archive_paths=matches,targeted_parent_paths=parents,
    shader_maps_parsed=false,assets_loaded=0,game_calls=0,
    current_process_RHI_determined=false
},Formatting.Indented));
Console.WriteLine("Shader archive filenames: " + matches.Length + "; game calls: 0");

"""Private path-keyed overlay package; current rig-selected skin identity wins."""
import argparse
import json
from pathlib import Path
from prepare_entity_overlay import prepare


def prepare_selected(root,output,paths):
    # Resource keys here are stable source paths, not pig/zombie kind aliases.
    manifest=prepare(root,output,{str(path):str(path)for path in paths})
    records=manifest.pop("skins")
    manifest["version"]=2
    manifest["skins_by_path"]={row["source_path"]:row for row in records.values()}
    (Path(output)/"index.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return manifest


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("private_entity_root");p.add_argument("private_overlay_root")
    p.add_argument("skin_paths",nargs="+",help="Exact selected skin relative paths from g.texture_path; no kind-based lookup.")
    a=p.parse_args()
    index=prepare_selected(a.private_entity_root,a.private_overlay_root,a.skin_paths)
    print(json.dumps(dict(version=2,selected_skin_paths=len(index["skins_by_path"]),local_only=True,shader_verified=False)))

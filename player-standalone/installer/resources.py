"""Extract personal Minecraft assets with the model branch's exact converter."""
import importlib.util
import json
import os
import shutil
import sys
import uuid
import zipfile
from pathlib import Path

from installer.core import (DEV, atomic_json, digest, ensure_no_session, fail, get_state,
                            operation_lock, owned_path)
from launcher.runtime import executable_role


def prepare_resources(root, minecraft_jar, packs=(), dry_run=False):
    root = Path(root).absolute()
    state = get_state(root)
    if state['manifest'].get('requirements', {}).get('assets_mode') == 'bundled-models-v4':
        fail('RESOURCE_V4_PROVIDER', '本完整候选已包含同批 Model4 资源，旧 V2 转换入口不能替代本版资源。',
             '个人 V4 提取须使用同批 V4/V3/V2 源、三份匹配 Jar SHA 的 geometry corpus、RGBA 准备与注册入口；此产品增量仍在对接。')
    jar = Path(minecraft_jar).resolve()
    wanted = state['manifest'].get('requirements', {}).get('minecraft_version', '26.3')
    try:
        with zipfile.ZipFile(jar) as archive:
            version = json.loads(archive.read('version.json'))
            if version.get('id') != wanted:
                fail('MC_VERSION', 'Minecraft 资源版本应为 ' + wanted + '。', '选择你已有安装中的对应客户端 jar；不要使用服务器 jar。')
            if not any(n.startswith('assets/minecraft/blockstates/') for n in archive.namelist()):
                fail('MC_ASSETS', '所选 jar 没有客户端方块资源。')
    except (OSError, KeyError, zipfile.BadZipFile, ValueError) as exc:
        fail('MC_JAR', '无法读取已有 Minecraft 客户端资源：' + str(exc))
    paths = [Path(p).resolve() for p in packs]
    for path in paths:
        if not path.is_file() or not zipfile.is_zipfile(path):
            fail('MC_PACK', '资源包不是有效的 ZIP：' + str(path))
    destination = owned_path(root, DEV + '/bridge/models')
    if dry_run:
        return {'ok': True, 'dry_run': True, 'minecraft_version': wanted, 'destination': str(destination),
                'resource_packs': len(paths), 'minecraft_jar_packaged': False}
    with operation_lock(root):
        ensure_no_session(root)
        processor = executable_role(root, state, 'model_processor')
        spec = importlib.util.spec_from_file_location('palcraft_owned_model_processor', processor)
        module = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(module)
        except ModuleNotFoundError as exc:
            fail('RESOURCE_DEPENDENCY', '资源转换缺少 Python 依赖：' + str(exc.name), '安装发布指南指定的 Pillow 依赖，再重新运行；没有下载任何游戏资源。')
        staging = owned_path(root, '.palcraft/staging/models-' + uuid.uuid4().hex)
        backup = owned_path(root, '.palcraft/resource-backup/models-' + uuid.uuid4().hex)
        try:
            converter = module.Converter(str(jar), str(staging), [str(p) for p in paths], 256)
            result = converter.prepare()
            if result.get('schema') != 2 or not result.get('models') or not result.get('textures'):
                fail('MC_EXTRACT', '资源转换没有产生可用模型或纹理。')
            # Missing ordinary geometry/textures is not silently reported as a completed installation.
            if result.get('issues'):
                fail('MC_EXTRACT_PARTIAL', '部分资源转换失败，已保留当前资源。', '使用受支持的原版资源或修复资源包中的缺失文件。')
            atomic_json(staging / 'personal-source.json', {'schema': 1, 'minecraft_version': wanted,
                        'minecraft_jar_sha256': digest(jar), 'resource_pack_sha256': [digest(p) for p in paths]})
            if destination.exists():
                backup.parent.mkdir(parents=True, exist_ok=True)
                os.replace(destination, backup)
            try:
                destination.parent.mkdir(parents=True, exist_ok=True)
                os.replace(staging, destination)
            except Exception:
                if backup.exists():
                    os.replace(backup, destination)
                raise
            return {'ok': True, 'models': result['models'], 'textures': result['textures'],
                    'special_models': len(result.get('special_models', [])), 'destination': str(destination),
                    'minecraft_jar_packaged': False, 'animation_rendered': result.get('animation_rendered', False)}
        finally:
            if staging.exists():
                shutil.rmtree(staging)

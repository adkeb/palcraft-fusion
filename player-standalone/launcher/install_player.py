#!/usr/bin/env python3
"""PalCraft 中文目录完整客户端的单一安装入口。"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer.core import PlayerError, read_json
from installer.setup import setup_player


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    labels = [('root', '新的个人安装目录'), ('game', '已有正版 Palworld 游戏目录'),
                       ('profile', '管理员提供的公开 profile.json'), ('credential', '个人 credential.json'),
                       ('guest-manifest', '同 UUID 的 guest.json')]
    for key, title in labels:
        parser.add_argument('--' + key, help=title)
    parser.add_argument('--interactive', action='store_true', help='中文引导填写安装参数')
    parser.add_argument('--bundle', default=str(Path(__file__).resolve().parents[1] / 'release.zip'))
    parser.add_argument('--minecraft-jar', help='可选：已有 Minecraft 26.3 客户端资源 jar')
    parser.add_argument('--previous-root', help='可选：旧个人安装目录，只生成同身份的后续存档迁移计划')
    parser.add_argument('--fabric-entry', help='可选：正常 Java/Fabric 注册 guest 启动入口；本命令不执行它')
    parser.add_argument('--source-user-dir', help='现存 UserDir，仅生成 runtime 正常退出后的增量迁移计划')
    parser.add_argument('--game-copy-mode', choices=('copy', 'apfs-clone'), default='copy', help='Mac 同一 APFS 卷可写时复制，避免重复占用大体积资产')
    parser.add_argument('--dry-run', action='store_true', help='完整检查，只生成计划')
    args = parser.parse_args()
    for key, title in labels:
        attribute = key.replace('-', '_')
        if getattr(args, attribute) is None:
            if not args.interactive:
                parser.error('需要 --' + key)
            setattr(args, attribute, input(title + '：').strip().strip('"').strip("'"))
    if args.interactive and not args.dry_run:
        print('先检查完整安装计划；输入 INSTALL 后安装到这个新个人目录。')
        args.dry_run = True
        interactive_profile = read_json(args.profile)
        interactive_profile['game_copy_mode'] = args.game_copy_mode
        preview = setup_player(args.root, args.game, args.bundle, interactive_profile, args.credential,
                               args.guest_manifest, previous_root=args.previous_root,
                               fabric_entry=args.fabric_entry, source_user_dir=args.source_user_dir, dry_run=True)
        print(json.dumps(preview, ensure_ascii=False, indent=2))
        if input('输入 INSTALL 开始：').strip() != 'INSTALL':
            return 0
        args.dry_run = False
    try:
        profile = read_json(args.profile)
        profile['game_copy_mode'] = args.game_copy_mode
        result = setup_player(args.root, args.game, args.bundle, profile, args.credential,
                              args.guest_manifest, minecraft_jar=args.minecraft_jar,
                              previous_root=args.previous_root, fabric_entry=args.fabric_entry,
                              source_user_dir=args.source_user_dir, dry_run=args.dry_run)
    except (PlayerError, OSError, ValueError) as exc:
        print(json.dumps(exc.as_dict() if isinstance(exc, PlayerError) else {'ok': False, 'message': str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

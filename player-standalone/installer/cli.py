"""Chinese player CLI and menu; all mutations have a side-effect-free dry run."""
import argparse
import json
import os
import sys
from pathlib import Path

from installer.core import (PlayerError, configure, fail, get_state, install, operation_lock,
                            read_json, recover_transactions, rollback, uninstall, update)
from installer.resources import prepare_resources
from launcher.runtime import (Session, create_bottle, diagnostics, health, recover_session,
                              run_worker, start, status, stop, promote)


def emit(value):
    print(json.dumps(value, ensure_ascii=False, indent=2))


def _path_input(text):
    return input(text).strip().strip('"').strip("'")


def player_menu(default_root=None):
    remembered = Path(__file__).resolve().parents[1] / '.player-root.json'
    root = default_root or read_json(remembered, {}).get('root')
    candidate = Path(__file__).resolve().parents[3]
    if not root and (candidate / '.palcraft/owner.json').is_file():
        root = str(candidate)
    while True:
        print('\nPalCraft 玩家工具')
        print('1 安装  2 启动  3 正常关闭  4 健康检查  5 更新  6 回退')
        print('7 诊断包  8 导入配置  9 提取 Minecraft 资源  P 正常/夜间/自定义帧率  0 保留存档卸载  Q 退出')
        choice = input('请选择：').strip().lower()
        if choice == 'q':
            return 0
        try:
            if choice == '1':
                profile_path = _path_input('服务器管理员提供的玩家 profile.json 路径：')
                profile = read_json(profile_path)
                root = _path_input('新的独立安装目录（Windows 可选 C/E 等盘；Mac 选择个人空目录）：')
                source = _path_input('你已有的正版 Palworld 游戏目录：')
                default_bundle = Path(__file__).resolve().parents[1] / 'release.zip'
                bundle = str(default_bundle) if default_bundle.is_file() else _path_input('本版 release.zip 路径：')
                preview = install(root, source, bundle, profile, dry_run=True)
                print('将复制', preview['game_files'], '个游戏文件；原游戏和已有存档只读。')
                print('至少需空闲', round(preview['required_free_bytes'] / 1024 ** 3, 2), 'GiB；专用存档目录：', preview['private_user_dir'])
                if input('输入 INSTALL 开始：').strip() != 'INSTALL':
                    continue
                emit(install(root, source, bundle, profile))
                remembered.write_text(json.dumps({'root': str(Path(root).absolute())}), encoding='utf-8')
                if profile['platform'] == 'crossover':
                    emit(create_bottle(root))
                print('下一步选择 9 从个人 Minecraft 提取资源，然后选择 4 检查。')
                continue
            if not root:
                root = _path_input('已有的独立安装目录：')
            if choice == '2':
                emit(start(root))
            elif choice == '3':
                emit(stop(root))
            elif choice == '4':
                emit(health(root, check_ports=status(root)['phase'] in ('stopped', 'failed')))
            elif choice == '5':
                bundle = _path_input('新版本 release.zip：')
                emit(update(root, bundle))
            elif choice == '6':
                emit(rollback(root))
            elif choice == '7':
                output = _path_input('保存诊断 ZIP 的路径：')
                emit(diagnostics(root, output))
            elif choice == '8':
                emit(configure(root, read_json(_path_input('新的 profile.json：'))))
            elif choice == '9':
                jar = _path_input('已有 Minecraft 客户端 jar（26.3）：')
                emit(prepare_resources(root, jar))
            elif choice == 'p':
                from installer.performance import set_performance
                preset = input('normal 正常60/60/30；night 夜间15/10/10；custom 自定义（Pal/MC/HUD）：').strip()
                values = [None, None, None]
                if preset == 'custom':
                    values = [int(input(title)) for title in ('帕鲁FPS：', '个人MC目标FPS：', '个人HUD目标FPS：')]
                emit(set_performance(root, preset, *values))
            elif choice == '0':
                emit(uninstall(root, dry_run=True))
                if input('输入 UNINSTALL 卸载（保留存档和专用bottle）：').strip() == 'UNINSTALL':
                    emit(uninstall(root))
        except (PlayerError, OSError, ValueError) as exc:
            emit(exc.as_dict() if isinstance(exc, PlayerError) else {'ok': False, 'message': str(exc)})
            print('没有操作服务器。按错误中的 action 提示处理后再试。')


def make_parser():
    parser = argparse.ArgumentParser(description='PalCraft 玩家安装、个人客户端启动和排错工具。')
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('install', 'configure', 'update', 'rollback', 'uninstall', 'bottle-create', 'form',
                 'resources', 'credential-import', 'performance', 'doctor', 'start', 'promote', 'stop', 'status', 'recover', 'recover-session', 'diagnostics', '_session', '_worker', '_proxy'):
        sub = commands.add_parser(name)
        sub.add_argument('--root', required=True, help='自己选择的独立安装目录')
        if name not in ('status', 'diagnostics', '_session', '_worker', '_proxy', 'doctor'):
            sub.add_argument('--dry-run', action='store_true', help='只检查并显示计划，不写文件、不联网、不启动进程')
        if name in ('install', 'update'):
            sub.add_argument('--bundle', required=True)
        if name == 'install':
            sub.add_argument('--game', required=True)
            sub.add_argument('--profile', required=True)
        if name == 'configure':
            sub.add_argument('--profile', required=True)
        if name == 'promote':
            sub.add_argument('--profile', help='正常登记已发布的当前本进程公开 profile；不写 runtime-config 或凭据')
        if name == 'form':
            sub.add_argument('--mode', choices=('on', 'off', 'status'), required=True)
        if name == 'credential-import':
            sub.add_argument('--credential', required=True)
            sub.add_argument('--guest-manifest', required=True)
        if name == 'performance':
            sub.add_argument('--preset', choices=('normal', 'night', 'custom'), required=True)
            sub.add_argument('--pal-fps', type=int)
            sub.add_argument('--mc-fps', type=int)
            sub.add_argument('--hud-fps', type=int)
        if name == 'resources':
            sub.add_argument('--minecraft-jar', required=True)
            sub.add_argument('--resource-pack', action='append', default=[])
        if name == 'doctor':
            sub.add_argument('--check-ports', action='store_true')
        if name == 'start':
            sub.add_argument('--boot-singleplayer', action='store_true',
                             help='仅以 bootstrap 阶段启动本地单机 Host/Game，观察真实 UID/authority；MC/HUD/AI 和动作授权仍待完整启动')
        if name == 'stop':
            sub.add_argument('--force', action='store_true', help='仅强制结束本次个人客户端；可能丢失未保存进度')
        if name == 'uninstall':
            sub.add_argument('--purge-saves', action='store_true', help='明确删除本安装的个人存档；默认保留')
        if name == 'diagnostics':
            sub.add_argument('--output', required=True)
        if name in ('_session', '_worker', '_proxy'):
            sub.add_argument('--token', required=True)
        if name == '_worker':
            sub.add_argument('--component', required=True)
            sub.add_argument('argv', nargs=argparse.REMAINDER)
    backend = commands.add_parser('backend-plan')
    backend.add_argument('--config', required=True)
    backend.add_argument('--output')
    backend.add_argument('--dry-run', action='store_true')
    menu = commands.add_parser('menu')
    menu.add_argument('--root')
    return parser


def main(argv=None):
    args = make_parser().parse_args(argv)
    command = args.command
    try:
        if command == 'menu':
            return player_menu(args.root)
        if command == 'backend-plan':
            from installer.backend_plan import build_backend_plan
            from installer.core import atomic_json
            result = build_backend_plan(read_json(args.config))
            if args.output and not args.dry_run:
                atomic_json(args.output, result)
            emit(result)
            return 0
        root = args.root
        dry = getattr(args, 'dry_run', False)
        if command == 'install':
            result = install(root, args.game, args.bundle, read_json(args.profile), dry)
        elif command == 'configure':
            result = configure(root, read_json(args.profile), dry)
        elif command == 'update':
            result = update(root, args.bundle, dry)
        elif command == 'rollback':
            result = rollback(root, dry)
        elif command == 'uninstall':
            result = uninstall(root, dry, args.purge_saves)
        elif command == 'bottle-create':
            result = create_bottle(root, dry)
        elif command == 'credential-import':
            from installer.credentials import import_credential
            result = import_credential(root, args.credential, args.guest_manifest, dry)
        elif command == 'performance':
            from installer.performance import set_performance
            result = set_performance(root, args.preset, args.pal_fps, args.mc_fps, args.hud_fps, dry)
        elif command == 'form':
            from launcher.form_request import request_form
            result = request_form(root, args.mode, dry)
        elif command == 'resources':
            result = prepare_resources(root, args.minecraft_jar, args.resource_pack, dry)
        elif command == 'doctor':
            result = health(root, args.check_ports)
        elif command == 'start':
            result = start(root, dry, boot_singleplayer=args.boot_singleplayer)
        elif command == 'promote':
            result = promote(root, read_json(args.profile) if args.profile else None, dry)
        elif command == 'stop':
            result = stop(root, args.force, dry)
        elif command == 'status':
            result = status(root)
        elif command == 'recover-session':
            result = recover_session(root, dry)
        elif command == 'recover':
            if dry:
                result = {'ok': True, 'dry_run': True, 'action': 'recover_incomplete_owned_install_transactions'}
            else:
                with operation_lock(root):
                    from installer.core import ensure_no_session
                    ensure_no_session(root)
                    result = {'ok': True, 'recovered_transactions': recover_transactions(root)}
        elif command == 'diagnostics':
            result = diagnostics(root, args.output)
        elif command == '_session':
            result = Session(root, args.token).run()
        elif command == '_proxy':
            import asyncio
            from launcher.session_proxy import run
            asyncio.run(run(root, args.token))
            return 0
        elif command == '_worker':
            argv = args.argv[1:] if args.argv and args.argv[0] == '--' else args.argv
            return run_worker(root, args.token, args.component, argv)
        else:
            fail('COMMAND_INVALID', '不支持该命令。')
        emit(result)
        return 0 if result.get('ok') else 2
    except PlayerError as exc:
        emit(exc.as_dict())
        return 2
    except (OSError, ValueError) as exc:
        emit({'ok': False, 'code': 'IO_ERROR', 'message': '本地文件或进程操作失败：' + str(exc),
              'action': '未操作服务器；运行 diagnostics 查看当前版本与健康检查。'})
        return 3


if __name__ == '__main__':
    raise SystemExit(main())

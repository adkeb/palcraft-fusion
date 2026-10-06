"""Verify the built mod and new mixin method targets without starting Minecraft."""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import zipfile

TARGETS = {
    'net/minecraft/world/entity/player/Player': [
        ('hurtServer', '(Lnet/minecraft/server/level/ServerLevel;Lnet/minecraft/world/damagesource/DamageSource;F)Z')],
    'net/minecraft/world/entity/LivingEntity': [
        ('heal', '(F)V'), ('die', '(Lnet/minecraft/world/damagesource/DamageSource;)V'), ('tickDeath', '()V'),
        ('startUsingItem', '(Lnet/minecraft/world/InteractionHand;)V')],
    'net/minecraft/world/food/FoodData': [('tick','(Lnet/minecraft/server/level/ServerPlayer;)V')],
    'net/minecraft/server/level/ServerPlayer': [
        ('teleportTo','(Lnet/minecraft/server/level/ServerLevel;DDDLjava/util/Set;FFZ)Z'),
        ('teleport','(Lnet/minecraft/world/level/portal/TeleportTransition;)Lnet/minecraft/server/level/ServerPlayer;')],
    'net/minecraft/server/network/ServerGamePacketListenerImpl': [
        ('handlePlayerAction','(Lnet/minecraft/network/protocol/game/ServerboundPlayerActionPacket;)V'),
        ('handleUseItemOn','(Lnet/minecraft/network/protocol/game/ServerboundUseItemOnPacket;)V'),
        ('handleUseItem','(Lnet/minecraft/network/protocol/game/ServerboundUseItemPacket;)V'),
        ('handleInteract','(Lnet/minecraft/network/protocol/game/ServerboundInteractPacket;)V'),
        ('handleContainerClick','(Lnet/minecraft/network/protocol/game/ServerboundContainerClickPacket;)V'),
        ('handleContainerButtonClick','(Lnet/minecraft/network/protocol/game/ServerboundContainerButtonClickPacket;)V')],
    'net/minecraft/world/level/Level': [
        ('setBlock', '(Lnet/minecraft/core/BlockPos;Lnet/minecraft/world/level/block/state/BlockState;II)Z'),
        ('blockEntityChanged', '(Lnet/minecraft/core/BlockPos;)V'),
        ('onBlockEntityAdded', '(Lnet/minecraft/world/level/block/entity/BlockEntity;)V')],
    'net/minecraft/server/level/ServerLevel': [
        ('sendBlockUpdated', '(Lnet/minecraft/core/BlockPos;Lnet/minecraft/world/level/block/state/BlockState;Lnet/minecraft/world/level/block/state/BlockState;I)V'),
        ('doBlockEvent', '(Lnet/minecraft/world/level/BlockEventData;)Z')],
    'net/minecraft/world/entity/Entity': [
        ('setAsInsidePortal', '(Lnet/minecraft/world/level/block/Portal;Lnet/minecraft/core/BlockPos;)V')],
    'net/minecraft/world/level/ServerExplosion': [
        ('explode', '()I'), ('center', '()Lnet/minecraft/world/phys/Vec3;'), ('radius', '()F'),
        ('getDirectSourceEntity', '()Lnet/minecraft/world/entity/Entity;'),
        ('level', '()Lnet/minecraft/server/level/ServerLevel;'),
        ('getBlockInteraction', '()Lnet/minecraft/world/level/Explosion$BlockInteraction;')],
    'net/minecraft/world/item/BlockItem': [
        ('getPlacementState', '(Lnet/minecraft/world/item/context/BlockPlaceContext;)Lnet/minecraft/world/level/block/state/BlockState;')],
}

def class_methods(data, return_fields=False):
    assert data[:4] == b'\xca\xfe\xba\xbe'
    position = 8
    def take(size):
        nonlocal position
        result = data[position:position+size]
        position += size
        return result
    def u2(): return struct.unpack('>H', take(2))[0]
    def u4(): return struct.unpack('>I', take(4))[0]
    count = u2()
    constants = [None] * count
    index = 1
    lengths = {3:4, 4:4, 5:8, 6:8, 7:2, 8:2, 9:4, 10:4, 11:4, 12:4, 15:3, 16:2, 17:4, 18:4, 19:2, 20:2}
    while index < count:
        tag = take(1)[0]
        if tag == 1: constants[index] = take(u2()).decode('utf-8', errors='replace')
        else: take(lengths[tag])
        index += 2 if tag in (5,6) else 1
    take(6)
    take(2 * u2())
    def member():
        flags, name, descriptor = u2(), constants[u2()], constants[u2()]
        for _ in range(u2()):
            take(2); take(u4())
        return name, descriptor, flags
    fields = {item[:2]:item[2] for item in (member() for _ in range(u2()))}
    if return_fields: return fields
    return {item[:2]: item[2] for item in (member() for _ in range(u2()))}

def verify(snapshot_root, minecraft_jar, reuse_checks_from=None):
    result = json.loads((snapshot_root/'build-result.json').read_text(encoding='utf-8-sig'))
    assert result['exit_code'] == 0, 'Build did not pass'
    log = (snapshot_root/'gradle-build.log').read_text(encoding='utf-8-sig')
    reuse=None
    if 'FeatureRegistryContract: PASS' not in log:
        assert reuse_checks_from is not None, 'Feature registration contract did not pass'
        reuse=json.loads((reuse_checks_from/'artifact-checks.json').read_text())
        prior=json.loads((reuse_checks_from/'source-manifest.json').read_text())
        current=json.loads((snapshot_root/'source-manifest.json').read_text())
        required_unchanged=[
            'build.gradle','src/main/java/dev/rehan/passthrough/FeatureRegistry.java',
            'src/main/java/dev/rehan/passthrough/CompleteLineJournal.java',
            'src/main/java/dev/rehan/passthrough/TravelAckValidator.java',
            'src/main/java/dev/rehan/passthrough/BridgeTravelGate.java',
            'src/contractTest/java/dev/rehan/passthrough/FeatureRegistryContract.java',
            'src/contractTest/java/dev/rehan/passthrough/TravelAckContract.java',
            'src/contractTest/resources/registered-guest-fixture.json',
            'src/contractTest/resources/registered-guest-fixture-b.json',
        ]
        for name in required_unchanged:
            assert current['files'][name]==prior['files'][name], 'Cannot reuse changed test implementation/input: '+name
        assert reuse['feature_registration_contract']=='PASS' and reuse['travel_contract']=='PASS' and reuse['registered_guest_manifest_contract']=='PASS'
    artifact = next(row for row in result['artifacts'] if row['name'].endswith('.jar') and '-sources' not in row['name'])
    jar = snapshot_root/artifact['name']
    assert hashlib.sha256(jar.read_bytes()).hexdigest() == artifact['sha256'], 'Downloaded jar mismatch'
    with zipfile.ZipFile(snapshot_root/'source.zip') as source:
        version = next(line.split('=',1)[1] for line in source.read('gradle.properties').decode().splitlines() if line.startswith('version='))
        if 'src/main/java/dev/rehan/passthrough/BridgeTravelGate.java' in source.namelist():
            assert 'TravelAckContract: PASS' in log or reuse is not None, 'Travel proof/journal contract did not pass'
        manifest = json.loads((snapshot_root/'source-manifest.json').read_text())
        for name, digest in manifest['files'].items():
            assert hashlib.sha256(source.read(name)).hexdigest() == digest, 'Source archive mismatch: ' + name
    if 'registeredGuestManifestCheck' in result['tasks']:
        assert 'RegisteredGuestManifestCheck: PASS' in log, 'Actual Loom manifest launch wiring did not pass'
    with zipfile.ZipFile(jar) as archive:
        mod = json.loads(archive.read('fabric.mod.json'))
        assert mod['version'] == version
        assert mod['depends']['java'] == '>=25'
        classes = [name for name in archive.namelist() if name.endswith('.class')]
        assert all(struct.unpack('>H',archive.read(name)[6:8])[0] == 69 for name in classes)
        mixins = []
        for resource, key in [('passthrough.mixins.json','mixins'),('passthrough.client.mixins.json','client')]:
            config = json.loads(archive.read(resource))
            assert len(config[key]) == len(set(config[key])), 'Duplicate mixin registration'
            for name in config[key]:
                path = config['package'].replace('.','/') + '/' + name + '.class'
                assert path in classes, 'Missing registered mixin: ' + name
                mixins.append(path)
        assert not any(name.startswith('net/minecraft/') for name in archive.namelist())
    targets = []
    with zipfile.ZipFile(minecraft_jar) as game:
        for target, required in TARGETS.items():
            methods = class_methods(game.read(target+'.class'))
            for name, descriptor in required:
                assert (name, descriptor) in methods, f'Missing exact mixin target: {target}.{name}{descriptor}'
                targets.append({'class':target.replace('/','.'),'method':name,'descriptor':descriptor,'access_flags':methods[(name,descriptor)]})
        login_fields=class_methods(game.read('net/minecraft/server/network/ServerLoginPacketListenerImpl.class'),return_fields=True)
        assert ('authenticatedProfile','Lcom/mojang/authlib/GameProfile;') in login_fields, 'Missing exact prelogin profile accessor field'
    checks = {
        'schema_version':1, 'snapshot':result['snapshot'], 'mod_version':mod['version'],
        'jar_sha256':artifact['sha256'], 'java_class_major':69, 'class_count':len(classes),
        'registered_mixin_count':len(mixins), 'feature_registration_contract':'PASS',
        'travel_contract':'PASS' if 'TravelAckContract: PASS' in log or reuse is not None else 'not_present_in_this_snapshot',
        'registered_guest_manifest_contract':'PASS' if 'RegisteredGuestManifestCheck: PASS' in log or reuse is not None else 'not_run',
        'test_evidence_source':str(reuse_checks_from) if reuse is not None else str(snapshot_root),
        'test_evidence_reused_for_identical_implementation_and_inputs':reuse is not None,
        'jar_hash':'PASS', 'mixin_registration_files':'PASS', 'minecraft_game_classes_absent':'PASS',
        'new_mixin_target_descriptors':'PASS', 'target_checks':targets,
        'login_profile_accessor_field':'PASS (actualMC26.3 authenticatedProfile GameProfile field)',
        'minecraft_oracle_sha256':hashlib.sha256(minecraft_jar.read_bytes()).hexdigest(),
        'runtime_validation':'pending_lead_deployment; target presence does not prove successful Mixin application'
    }
    (snapshot_root/'artifact-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({key:value for key,value in checks.items() if key!='target_checks'},ensure_ascii=False))
    return checks

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--snapshot-root',type=Path,required=True)
    parser.add_argument('--minecraft-jar',type=Path,required=True)
    parser.add_argument('--reuse-checks-from',type=Path)
    args = parser.parse_args()
    verify(args.snapshot_root,args.minecraft_jar,args.reuse_checks_from)

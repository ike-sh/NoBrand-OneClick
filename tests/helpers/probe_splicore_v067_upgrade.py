#!/usr/bin/env python3
"""Exercise a real v4.2.0/v0.6.5 node set, witnessed upgrade, backup and rollback.

Run as root on Linux amd64 with a full Git checkout; host init and firewall alone
are substituted. Every listener and target is private loopback. No SQL access.
"""
import argparse
import contextlib
import gzip
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import tarfile
import tempfile
from unittest.mock import patch

from probe_splicore_v065 import listener_pair_port, revision_and_ids, tcp_exchange, udp_exchange
from splicore_native_probe import Echo, MIHOMO_SHA256, ROOT, Supervisor, check, sc, stop, traffic as mihomo_traffic, vacant

MANAGER = '1e0440db392ca79d4ba2b6a0507ecec4c3d06f45'  # v4.2.0


def historical_manager(work):
    dest = work / 'old-manager'
    dest.mkdir(mode=0o700)
    for name in ('splicore.py', 'splicore-release.json', 'splicore-launch.py'):
        data = subprocess.check_output(['git', '-c', 'safe.directory=' + str(ROOT), 'show',
                                        MANAGER + ':runtime/' + name], cwd=ROOT)
        (dest / name).write_bytes(data)
    spec = importlib.util.spec_from_file_location('previous_manager', dest / 'splicore.py')
    old = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old)
    check(old.RELEASE['version'] == 'v0.6.5', 'old manager has wrong pin')
    return old


def refused(operation, category):
    try:
        operation()
    except sc.Failure as exc:
        check(exc.category == category, 'unexpected rejection: ' + exc.category + ': ' + str(exc))
    else:
        raise AssertionError('expected rejection: ' + category)


def run(old_assets, assets, mihomo_gzip=None):
    os.umask(0o077)
    result = {'manager_baseline': MANAGER, 'old_core': 'v0.6.5', 'core': sc.RELEASE['version'],
              'scope': 'Linux amd64; private loopback, real daemons and storage; init and firewall substituted', 'checks': {}}
    checks = result['checks']
    with tempfile.TemporaryDirectory(prefix='sc67-') as tmp, Echo() as echo, contextlib.ExitStack() as stack:
        work = Path(tmp)
        env = {k: str(work / v) for k, v in {'NOBRAND_STATE_DIR': 's', 'NOBRAND_CONFIG_DIR': 'c', 'NOBRAND_LIB_DIR': 'l',
                                             'NOBRAND_LIFECYCLE_DIR': 'j', 'NOBRAND_LIFECYCLE_LOCK_FILE': 'lock',
                                             'NOBRAND_SPLICORE_UNIT': 'unit'}.items()}
        env.update(NOBRAND_SYSTEM_ROOT=str(work), NOBRAND_SPLICORE_LISTEN='127.0.0.1', NOBRAND_SPLICORE_MANAGER_SOURCE='',
                   ADVERTISE_HOST='127.0.0.1', ADVERTISE_PORT='')
        stack.enter_context(patch.dict(os.environ, env))
        old = historical_manager(work)
        previous, runtime = old.Runtime(adapter='systemd'), sc.Runtime(adapter='systemd')
        supervisor = Supervisor(runtime, stack.enter_context((work / 'private.log').open('wb')))
        stack.callback(lambda: stop(supervisor.child))
        for module in (old, sc):
            stack.enter_context(patch.object(module.Service, 'call', lambda service, *a, **kw: supervisor.call(service, *a, **kw)))
            stack.enter_context(patch.object(module.Runtime, 'firewall'))
        fixtures = [('mieru', 'm', {'PROTOCOL': 'BOTH', 'USERNAME': 'fixture-mieru', 'TRAFFIC_PATTERN': 'off'}),
                    ('snell', 's4', {'SNELL_VERSION': '4'}), ('snell', 's5', {'SNELL_VERSION': '5'}),
                    ('vless-reality', 'r', {'VLESS_REALITY_TARGET': 'localhost', 'VLESS_REALITY_TARGET_PORT': '443'}),
                    ('vless-sudoku', 'v', {}), ('hysteria2', 'h', {}), ('tuic', 't', {}),
                    ('socks5', 'proxy', {'USERNAME': 'fixture-local', 'SOCKS5_UDP': 'on'})]
        for index, (kind, name, values) in enumerate(fixtures):
            port = listener_pair_port() if kind == 'mieru' else vacant(socket.SOCK_DGRAM if kind in ('tuic', 'hysteria2') else socket.SOCK_STREAM)
            with patch.dict(os.environ, dict(values, PORT=str(port))):
                previous.protocol(kind, 'install', name, old_assets if index == 0 else None)
        old_gen = previous.current.resolve()
        graph = previous.desired()
        profile = previous.protocol('socks5', 'export', 'proxy')
        key = (old_gen / 'runtime/master.key').read_bytes()
        ids = revision_and_ids(previous)
        count = len(ids[1])
        check(count == 9, 'old node fixture incomplete')
        legacy_snell = [(node['client']['name'], old.client_profiles(node)['mihomo'])
                        for node in graph['nodes'] if node['protocol'] == 'snell']
        if mihomo_gzip:
            check(sc.sha(mihomo_gzip) == MIHOMO_SHA256, 'wrong pinned Mihomo peer')
            with gzip.open(mihomo_gzip, 'rb') as stream:
                sc.atomic(work / 'mihomo', stream.read(), 0o700)

        def traffic():
            proxy = ('127.0.0.1', profile['port'])
            tcp_exchange(proxy, profile, echo.tcp.server_address)
            udp_exchange(proxy, profile, echo.udp.server_address, '127.0.0.1')
            if mihomo_gzip:
                for name, fragment in legacy_snell:
                    mihomo_traffic(work, work / 'mihomo', supervisor.log, echo, fragment, name, udp=True)
                checks['frozen_v065_snell4_and_snell5_tcp_udp_stages'] = checks.get('frozen_v065_snell4_and_snell5_tcp_udp_stages', 0) + 1

        traffic()
        checks['v065_baseline'] = {'healthy_listeners': previous.health(old_gen)['inbound_count'], 'socks5_tcp_udp_payload': True}
        legacy_backup = work / 'legacy.tgz'
        previous.backup(legacy_backup)
        journal = runtime.transaction.read_bytes()
        pid = supervisor.child.pid
        refused(lambda: runtime.deploy(graph, assets), 'WITNESS_ACK_REQUIRED')
        check(runtime.current.resolve() == old_gen and supervisor.child.pid == pid and journal == runtime.transaction.read_bytes(),
              'implicit upgrade affected service or journal')
        checks['implicit_baseline_refused_before_cutover'] = True
        runtime.deploy(graph, assets, acknowledge=True)
        new = runtime.current.resolve()
        db = new / 'runtime/state.db'
        witness = new / 'runtime/state.db.witness'
        inspection = sc.inspect_state(new / 'splicore', db)
        check(inspection['lineage'] == 'legacy_baseline' and not inspection['historical_proof'] and not (old_gen / 'runtime/state.db.witness').exists(),
              'incorrect baseline lineage or old generation modified')
        check(runtime.desired()['nodes'] == graph['nodes'] and revision_and_ids(runtime) == ids
              and (new / 'runtime/master.key').read_bytes() == key and runtime.protocol('socks5', 'export', 'proxy') == profile,
              'logical state, identities, revision, credentials or key changed')
        traffic()
        checks['v067_upgrade'] = {'healthy_listeners': runtime.health(new)['inbound_count'], 'snapshot_revision': ids[0],
                                  'inbound_binding_account_ids_unchanged': True, 'graph_credentials_and_key_unchanged': True,
                                  'lineage': inspection['lineage'], 'historical_proof': inspection['historical_proof'], 'socks5_tcp_udp_payload': True}
        runtime.start(restart=True)
        traffic()
        checks['v067_restart'] = True
        snapshot = work / 'current.tgz'
        runtime.backup(snapshot)
        with tarfile.open(snapshot) as tar:
            check({'runtime/state.db', 'runtime/master.key', 'runtime/state.db.witness'} <= set(tar.getnames()) and
                  tar.extractfile('runtime/state.db.witness').read() == witness.read_bytes(), 'backup lost matched witness')
        product = work / 'product.tgz'
        runtime.backup(product, unified=True)
        sc.inspect_backup_archive(product)
        with tarfile.open(product) as tar:
            names = set(tar.getnames())
            for g in (old_gen, new):
                prefix = 'state/splicore/generations/' + g.name + '/runtime/'
                check({prefix + 'state.db', prefix + 'master.key'} <= names and ((prefix + 'state.db.witness') in names) == (g == new),
                      'product backup contains unmatched generations')
        checks['standalone_and_product_backups_match_generations'] = True
        runtime.rollback()
        check(runtime.current.resolve() == old_gen and runtime.desired() == graph and revision_and_ids(runtime) == ids,
              'rollback changed the original generation')
        traffic()
        checks['rollback_to_original_v065_including_socks5_payload'] = True
        runtime.restore(snapshot, assets)
        restored = runtime.current.resolve()
        check(sc.inspect_state(restored / 'splicore', restored / 'runtime/state.db') == inspection and revision_and_ids(runtime) == ids,
              'standalone restore replaced rather than restored the original DB')
        traffic()
        checks['standalone_restore_retains_db_ids_witness_key_and_payload'] = True
        refused(lambda: runtime.restore(legacy_backup, assets), 'WITNESS_ACK_REQUIRED')
        runtime.restore(legacy_backup, assets, acknowledge=True)
        check(revision_and_ids(runtime) == ids and runtime.protocol('socks5', 'export', 'proxy') == profile,
              'standalone pre-witness backup lost original identities')
        current, prior = runtime.current.resolve(), runtime.previous.resolve()
        runtime.stop()
        # Restored pointers are plain ownership records. Corrupt only the private test
        # copy of the previous witness: adoption must leave BOTH records untouched.
        for link, generation in ((runtime.current, current), (runtime.previous, prior)):
            link.unlink()
            sc.save(link, {'owner': 'nobrand-splicore-pointer-v1', 'generation': generation.name})
        sidecar = prior / 'runtime/state.db.witness'
        saved = sidecar.read_bytes()
        sidecar.write_bytes(b'broken fixture')
        refused(runtime.adopt_snapshot, 'STORAGE_INTEGRITY')
        check(not runtime.current.is_symlink() and not runtime.previous.is_symlink() and sidecar.read_bytes() == b'broken fixture',
              'adoption changed pointers or suspect witness')
        sidecar.write_bytes(saved)
        runtime.adopt_snapshot()
        pending = current / 'runtime/state.db.witness.pending'
        pending.write_bytes(b'fixture evidence')
        refused(lambda: runtime.backup(work / 'pending.tgz'), 'STORAGE_INTEGRITY')
        check(pending.read_bytes() == b'fixture evidence' and not (work / 'pending.tgz').exists(), 'pending evidence was discarded')
        checks['corrupt_previous_witness_and_pending_current_fail_closed'] = True
        pending.unlink()  # Test teardown only; never repair a production generation this way.
        runtime.start()
        traffic()
        checks['legacy_backup_requires_ack_and_restores_original_identities'] = True
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--old-artifacts', type=Path, required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--mihomo-gzip', type=Path, help='optional pinned Mihomo v1.19.30 for frozen Snell v4/v5 profile traffic')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = run(args.old_artifacts.resolve(), args.artifacts.resolve(), args.mihomo_gzip)
    if args.output:
        sc.save(args.output, result)
    print(json.dumps(result, indent=2))

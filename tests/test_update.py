"""Tests for config/update.py (stdlib only; run with python3 -m unittest)."""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'config' / 'update.py'
TEMPLATE = ROOT / 'agents' / 'agent-youtube.md'

READ_ONLY = ['whoami', 'write_context', 'write_channel_list', 'list', 'transcript', 'preview',
             'best_publish_times', 'upload_reconcile', 'upload_reconcile_many', 'playlist_list',
             'social_accounts', 'social_queue']
OPERATOR = ['write_channel_select', 'auth_user_select', 'apply', 'upload_multi', 'upload_cancel',
            'playlist_create', 'playlist_update', 'playlist_delete', 'playlist_add_videos',
            'playlist_remove_videos', 'social_stage_video', 'social_preview', 'social_confirm',
            'social_cancel', 'social_reschedule']


def snapshot(directory):
    return {str(p.relative_to(directory)): p.read_bytes() for p in sorted(Path(directory).rglob('*'))
            if p.is_file()}


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.agent = self.tmp / 'agent'
        self.agent.mkdir()
        self.tm = self.tmp / 'tm'
        self.tm.mkdir()
        self.bin = self.tmp / 'bin'
        self.bin.mkdir()
        self.npm = self.bin / 'npm'
        self.npm.write_text('#!/bin/sh\n')
        self.npm.chmod(0o755)
        self.voice = self.tmp / 'voice.md'
        self.skills = self.tmp / 'skills'

    def run_update(self, action='install', *, tm=None, extra=(), env=None, path=None, full=True):
        cmd = [sys.executable, str(SCRIPT), action, '--agent-dir', str(self.agent),
               '--tubemaster', str(tm or self.tm)]
        if full:
            cmd += ['--template', str(TEMPLATE), '--voice', str(self.voice),
                    '--skills-dir', str(self.skills)]
        cmd += list(extra)
        environ = {'PATH': path if path is not None else str(self.bin), 'HOME': str(self.tmp)}
        environ.update(env or {})
        return subprocess.run(cmd, capture_output=True, text=True, env=environ, timeout=30)

    def install(self, **kw):
        r = self.run_update('install', **kw)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def read(self, name):
        return json.loads((self.agent / name).read_text())

    def agent_text(self):
        return (self.agent / 'agents' / 'agent-youtube.md').read_text()

    def frontmatter_tools(self):
        return [l.strip()[2:] for l in self.agent_text().splitlines() if l.startswith('  - ')]

    def assert_rejected(self, result, code, text, before):
        self.assertEqual(result.returncode, code, result.stderr)
        self.assertIn(text, result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual(snapshot(self.tmp), before)

    # --- S2: usage errors -------------------------------------------------
    def test_invalid_action_exits_2_and_touches_nothing(self):
        (self.agent / 'mcp.json').write_text('{"mcpServers": {"tubemaster": {"x": 1}}}')
        before = snapshot(self.tmp)
        r = self.run_update('typo_action')
        self.assert_rejected(r, 2, 'invalid choice', before)

    def test_wrong_arity_exits_2_and_touches_nothing(self):
        before = snapshot(self.tmp)
        r = subprocess.run([sys.executable, str(SCRIPT), 'install'], capture_output=True, text=True,
                           env={'PATH': str(self.bin)}, timeout=30)
        self.assertEqual(r.returncode, 2)
        self.assertIn('--agent-dir', r.stderr)
        self.assertNotIn('Traceback', r.stderr)
        r = self.run_update('install', extra=['stray'])
        self.assert_rejected(r, 2, 'unrecognized arguments', before)
        r = self.run_update('install', full=False)
        self.assert_rejected(r, 2, '--template', before)

    def test_invalid_effort_is_usage_error(self):
        before = snapshot(self.tmp)
        r = self.run_update(env={'AGENT_YOUTUBE_EFFORT': 'turbo'})
        self.assert_rejected(r, 2, 'AGENT_YOUTUBE_EFFORT', before)

    def test_help_exits_0(self):
        r = subprocess.run([sys.executable, str(SCRIPT), '--help'], capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0)
        for word in ('--force', 'AGENT_YOUTUBE_MODEL', 'AGENT_YOUTUBE_OPERATOR'):
            self.assertIn(word, r.stdout)

    # --- fresh install, rendering, manifest -------------------------------
    def test_fresh_install_writes_entries_agent_and_manifest(self):
        r = self.install()
        lines = r.stdout.splitlines()
        self.assertEqual(len(lines), 3)
        self.assertTrue(all(l.startswith('installed: ') for l in lines), r.stdout)
        mcp = self.read('mcp.json')['mcpServers']['tubemaster']
        self.assertEqual(mcp['command'], str(self.npm))
        self.assertEqual(mcp['cwd'], str(self.tm))
        self.assertEqual(self.read('subagents.json')['model_profiles']['agent-youtube'], {'effort': 'high'})
        manifest = self.read('agent-youtube.manifest.json')
        self.assertEqual(manifest['entries']['mcp.json'], mcp)
        self.assertEqual(manifest['agent_file_sha256'],
                         hashlib.sha256((self.agent / 'agents' / 'agent-youtube.md').read_bytes()).hexdigest())
        again = self.install()
        self.assertTrue(all(l.startswith('unchanged: ') for l in again.stdout.splitlines()), again.stdout)

    def test_agent_file_is_rendered_from_template(self):
        self.install()
        text = self.agent_text()
        self.assertNotIn('{{', text)
        self.assertIn(str(self.voice), text)
        self.assertIn(f'{self.skills}/yt-audit/SKILL.md', text)
        self.assertNotIn('~/.agents/skills', text)
        self.assertIn('thinking: high', text)
        self.assertNotIn('\nmodel:', text)
        for word in ('web_search', 'fetch_content', 'yt-dlp'):
            self.assertIn(word, text)
        self.assertNotIn('post replies', text)
        self.assertIn('watch-video', text)
        self.assertIn('AGENT_YOUTUBE_OPERATOR=1', text)

    def test_model_and_effort_env_reach_both_files(self):
        self.install(env={'AGENT_YOUTUBE_MODEL': 'acme/model-1', 'AGENT_YOUTUBE_EFFORT': 'max'})
        self.assertEqual(self.read('subagents.json')['model_profiles']['agent-youtube'],
                         {'model': 'acme/model-1', 'effort': 'max'})
        text = self.agent_text()
        self.assertIn('\nmodel: acme/model-1\n', text)
        self.assertIn('\nthinking: max\n', text)

    def test_operator_tool_set(self):
        self.install()
        tools = self.frontmatter_tools()
        for name in READ_ONLY:
            self.assertIn(f'mcp__tubemaster__{name}', tools)
        for name in OPERATOR:
            self.assertNotIn(f'mcp__tubemaster__{name}', tools)
        self.install(env={'AGENT_YOUTUBE_OPERATOR': '1'})
        tools = self.frontmatter_tools()
        for name in READ_ONLY + OPERATOR:
            self.assertIn(f'mcp__tubemaster__{name}', tools)

    def test_missing_npm_fails_without_writing(self):
        before = snapshot(self.tmp)
        r = self.run_update(path=str(self.tmp / 'nowhere'))
        self.assert_rejected(r, 1, 'npm', before)

    # --- invalid JSON -----------------------------------------------------
    def test_malformed_json(self):
        (self.agent / 'mcp.json').write_text('{"mcpServers": ')
        before = snapshot(self.tmp)
        r = self.run_update()
        self.assert_rejected(r, 1, 'mcp.json: invalid JSON', before)

    def test_jsonc_message(self):
        (self.agent / 'subagents.json').write_text('{\n // note\n "model_profiles": {},\n}\n')
        before = snapshot(self.tmp)
        r = self.run_update()
        self.assert_rejected(r, 1, 'invalid JSON (comments and trailing commas are not supported)', before)

    # --- conflicts and --force -------------------------------------------
    def test_conflicting_entry_without_and_with_force(self):
        mine = {'type': 'stdio', 'command': 'mine'}
        (self.agent / 'mcp.json').write_text(json.dumps({'mcpServers': {'tubemaster': mine}}))
        before = snapshot(self.tmp)
        r = self.run_update()
        self.assert_rejected(r, 1, 'mcpServers.tubemaster', before)
        self.assertIn('--force', r.stderr)
        r = self.run_update(extra=['--force'])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('updated: ', r.stdout)
        self.assertEqual(self.read('mcp.json')['mcpServers']['tubemaster']['command'], str(self.npm))
        backups = list(self.agent.glob('mcp.json.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(json.loads(backups[0].read_text()), {'mcpServers': {'tubemaster': mine}})

    def test_modified_agent_file_conflict_and_force_backup(self):
        self.install()
        path = self.agent / 'agents' / 'agent-youtube.md'
        path.write_text('my edits\n')
        before = snapshot(self.tmp)
        r = self.run_update()
        self.assert_rejected(r, 1, 'agent-youtube.md', before)
        r = self.run_update(extra=['--force'])
        self.assertEqual(r.returncode, 0, r.stderr)
        backups = list(path.parent.glob('agent-youtube.md.bak.*'))
        self.assertEqual([b.read_text() for b in backups], ['my edits\n'])
        self.assertNotEqual(path.read_text(), 'my edits\n')

    # --- permissions, symlinks -------------------------------------------
    def test_permissions_preserved(self):
        for name, mode in (('mcp.json', 0o644), ('subagents.json', 0o640)):
            (self.agent / name).write_text('{}')
            (self.agent / name).chmod(mode)
        self.install()
        self.assertEqual((self.agent / 'mcp.json').stat().st_mode & 0o777, 0o644)
        self.assertEqual((self.agent / 'subagents.json').stat().st_mode & 0o777, 0o640)

    def test_new_files_are_0644(self):
        self.install()
        self.assertEqual((self.agent / 'mcp.json').stat().st_mode & 0o777, 0o644)

    def test_dangling_symlink_fails_and_creates_nothing(self):
        (self.agent / 'mcp.json').symlink_to(self.tmp / 'dots' / 'mcp.json')
        before = snapshot(self.tmp)
        r = self.run_update()
        self.assert_rejected(r, 1, 'dangling symlink', before)
        self.assertFalse((self.tmp / 'dots').exists())

    def test_symlinked_existing_config_writes_through(self):
        dots = self.tmp / 'dots'
        dots.mkdir()
        (dots / 'mcp.json').write_text('{"other": 1}')
        (self.agent / 'mcp.json').symlink_to(dots / 'mcp.json')
        self.install()
        self.assertTrue((self.agent / 'mcp.json').is_symlink())
        data = json.loads((dots / 'mcp.json').read_text())
        self.assertEqual(data['other'], 1)
        self.assertIn('tubemaster', data['mcpServers'])
        self.assertEqual(len(list(self.agent.glob('mcp.json.bak.*'))), 1)
        self.assertEqual(list(dots.glob('*.bak.*')), [])

    # --- upgrade and uninstall -------------------------------------------
    def test_manifest_upgrade_when_tubemaster_moves(self):
        self.install()
        new_tm = self.tmp / 'moved'
        new_tm.mkdir()
        r = self.install(tm=new_tm)
        self.assertIn('updated: ', r.stdout)
        self.assertEqual(self.read('mcp.json')['mcpServers']['tubemaster']['cwd'], str(new_tm))
        self.assertEqual(self.read('agent-youtube.manifest.json')['entries']['mcp.json']['cwd'], str(new_tm))

    def test_model_change_upgrades_managed_entries(self):
        self.install()
        r = self.install(env={'AGENT_YOUTUBE_MODEL': 'acme/two'})
        self.assertEqual(sum(l.startswith('updated: ') for l in r.stdout.splitlines()), 2, r.stdout)
        self.assertEqual(self.read('subagents.json')['model_profiles']['agent-youtube']['model'], 'acme/two')

    def test_uninstall_removes_everything_and_empty_sections(self):
        (self.agent / 'mcp.json').write_text('{"keep": true}')
        self.install()
        r = self.run_update('uninstall', full=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sum(l.startswith('removed: ') for l in r.stdout.splitlines()), 3, r.stdout)
        self.assertEqual(self.read('mcp.json'), {'keep': True})
        self.assertEqual(self.read('subagents.json'), {})
        self.assertFalse((self.agent / 'agents' / 'agent-youtube.md').exists())
        self.assertFalse((self.agent / 'agent-youtube.manifest.json').exists())

    def test_uninstall_skips_modified_entry_and_reports_it(self):
        self.install()
        data = self.read('subagents.json')
        data['model_profiles']['agent-youtube']['effort'] = 'low'
        (self.agent / 'subagents.json').write_text(json.dumps(data))
        r = self.run_update('uninstall', full=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('skipped (modified): ', r.stdout)
        self.assertIn('subagents.json model_profiles.agent-youtube', r.stdout)
        self.assertIn('skipped (modified)', r.stderr)
        self.assertEqual(self.read('subagents.json'), data)
        self.assertNotIn('tubemaster', self.read('mcp.json').get('mcpServers', {}))
        self.assertTrue((self.agent / 'agent-youtube.manifest.json').exists())
        self.assertNotIn('mcp.json', self.read('agent-youtube.manifest.json')['entries'])

    def test_uninstall_skips_modified_agent_file(self):
        self.install()
        path = self.agent / 'agents' / 'agent-youtube.md'
        path.write_text('mine\n')
        r = self.run_update('uninstall', full=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('skipped (modified): ', r.stdout)
        self.assertEqual(path.read_text(), 'mine\n')

    # --- legacy (555cdd0) installs without a manifest ---------------------
    def legacy(self):
        (self.agent / 'mcp.json').write_text(json.dumps({'mcpServers': {'tubemaster': {
            'type': 'stdio', 'command': 'npm', 'args': ['run', 'mcp:video-metadata'],
            'cwd': str(self.tm), 'env': {'npm_config_loglevel': 'silent'}, 'exposure': 'direct'}}}))
        (self.agent / 'subagents.json').write_text(json.dumps({'model_profiles': {'agent-youtube': {
            'model': 'cpamc/deeprelay/deepseek-v4.1-flash', 'effort': 'high'}}}))

    def test_legacy_install_is_upgraded(self):
        self.legacy()
        r = self.install()
        self.assertIn('updated: ', r.stdout)
        self.assertEqual(self.read('mcp.json')['mcpServers']['tubemaster']['command'], str(self.npm))
        self.assertEqual(self.read('subagents.json')['model_profiles']['agent-youtube'], {'effort': 'high'})
        self.assertTrue((self.agent / 'agent-youtube.manifest.json').exists())

    def test_legacy_install_is_uninstalled(self):
        self.legacy()
        r = self.run_update('uninstall', full=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.read('mcp.json'), {})
        self.assertEqual(self.read('subagents.json'), {})


if __name__ == '__main__':
    unittest.main()

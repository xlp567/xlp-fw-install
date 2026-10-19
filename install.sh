#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
command -v python3 >/dev/null 2>&1 || { echo '需要 Python 3；Debian/Ubuntu 可先执行 apt-get update && apt-get install -y python3' >&2; exit 1; }
python3 -I - "$@" <<'XLP_FW_BOOTSTRAP_PY'
"""Public entry point: download a pinned installer; no firewall policy or secrets."""
import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

REPOSITORY = 'xlp567/xlp-fw'
INSTALLER_COMMIT = 'd72887fcadd7159a1b817a98900c60ecc5e19e96'
INSTALLER_SHA256 = '203e57011993a15c947b104c8ad39df5c841a89b3faff91a50ccaf24611d4e38'
TOKEN_FILE = Path('/var/lib/xlp-fw/github-token')
LIMIT = 2 * 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('下载返回重定向，已阻止转发令牌')


def read_token(path):
    p = Path(path)
    if p.is_symlink():
        raise ValueError('令牌文件不得为符号链接')
    if not p.exists():
        return ''
    if not p.is_file() or p.stat().st_size > 4098 or stat.S_IMODE(p.stat().st_mode) & 0o077:
        raise ValueError('令牌文件必须是权限 600 或更严格的小型普通文件')
    return p.read_text().strip()


def fetch_installer(token):
    url = 'https://api.github.com/repos/' + REPOSITORY + '/contents/install.py?ref=' + INSTALLER_COMMIT
    req = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'xlp-fw-bootstrap',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response:
            raw = response.read(LIMIT + 1)
    except urllib.error.HTTPError as exc:
        raise ValueError('GitHub 读取失败（HTTP %s）；确认令牌授权 xlp-fw 仓库 Contents: Read-only。旧令牌过期时加 --new-token 重试。' % exc.code) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ValueError('无法连接 GitHub，原脚本保持不变') from None
    if len(raw) > LIMIT:
        raise ValueError('GitHub 响应过大')
    item = json.loads(raw)
    if item.get('type') != 'file' or item.get('encoding') != 'base64':
        raise ValueError('安装器下载格式异常')
    data = base64.b64decode(''.join(item['content'].split()), validate=True)
    if hashlib.sha256(data).hexdigest() != INSTALLER_SHA256:
        raise ValueError('安装器 SHA-256 校验失败，未执行')
    return data


def main(argv=None):
    parser = argparse.ArgumentParser(description='XLP-FW 一键安装 / 升级（防火墙主仓库保持私有）')
    parser.add_argument('--check', action='store_true', help='只检查下载，不安装')
    parser.add_argument('--new-token', action='store_true', help='重新隐藏输入令牌')
    parser.add_argument('--token-file', type=Path, help='从权限 600 的文件读取令牌')
    args = parser.parse_args(argv)
    if sys.platform != 'linux':
        raise ValueError('请在 Linux 服务器上执行')
    if os.geteuid() != 0:
        raise ValueError('请在 root SSH 终端执行')
    token = '' if args.new_token else read_token(args.token_file or TOKEN_FILE)
    if token:
        print('已读取服务器保存的 GitHub 只读令牌。')
    else:
        # Refuse fallback to echoed stdin: the shell supplies this program on stdin.
        with open('/dev/tty'):
            pass
        token = getpass.getpass('GitHub 只读令牌（仅 xlp-fw 仓库 Contents: Read-only，隐藏输入）: ').strip()
    if not re.fullmatch(r'[\x21-\x7e]{10,4096}', token):
        raise ValueError('令牌格式无效')
    print('正在下载并校验安装器……')
    data = fetch_installer(token)
    with tempfile.TemporaryDirectory(prefix='xlp-fw-bootstrap-') as work:
        installer = Path(work) / 'install.py'
        installer.write_bytes(data)
        installer.chmod(0o600)
        token_path = Path(work) / 'token'
        fd = os.open(token_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(token)
        command = [sys.executable, '-I', str(installer), '--token-file', str(token_path)]
        if args.check:
            command.append('--check')
            subprocess.run(command, check=True)
        else:
            # The child needs a terminal for its install confirmation, not the heredoc.
            with open('/dev/tty') as tty:
                subprocess.run(command, stdin=tty, check=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        print('错误：' + str(exc), file=sys.stderr)
        sys.exit(1)

XLP_FW_BOOTSTRAP_PY

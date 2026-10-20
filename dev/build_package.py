"""Build the shareable preset (the GitHub repository folder) from the live Nilesoft Shell config.

Usage: python -I build_package.py <nilesoft dir> <package dir>

  config/ru  - shell.nss + the imported files (Russian, as in the live config) with an empty paths.nss
  config/en  - the same files translated by i18n/translate.py
  setup/     - install.ps1;  Install.cmd in the root starts it
  dev/       - generators, translation dictionaries and the checker
README*.md, MENU*.md and LICENSE in the package root are written by hand and kept as they are.
"""
import os
import re
import shutil
import subprocess
import sys

src, pkg = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
py = [sys.executable, '-I']


def fix_text(path):
    """In the package the generators live in dev/, not in the author's dev/ folder."""
    raw = open(path, 'rb').read()
    bom = raw.startswith(b'\xef\xbb\xbf')
    t = raw.decode('utf-8-sig').replace('dev/', 'dev/')
    open(path, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + t.encode('utf-8'))


for sub in ('config', 'setup', 'dev'):
    shutil.rmtree(os.path.join(pkg, sub), ignore_errors=True)
for old in ('Установить.cmd',):
    if os.path.exists(os.path.join(pkg, old)):
        os.remove(os.path.join(pkg, old))

ru = os.path.join(pkg, 'config', 'ru')
en = os.path.join(pkg, 'config', 'en')
os.makedirs(os.path.join(ru, 'imports'))
os.makedirs(os.path.join(en, 'imports'))

shell = open(os.path.join(src, 'shell.nss'), encoding='utf-8-sig').read()
imports = re.findall(r"^import\s+'imports/([^']+)'", shell, re.M)
names = ['shell.nss'] + ['imports/' + n for n in imports + ['ffmpeg-run.ps1', 'tools-run.ps1']]
for name in names:
    dst = os.path.join(ru, name)
    if name == 'imports/paths.nss':
        subprocess.run(py + [os.path.join(here, 'build_paths_nss.py'), dst], check=True, stdout=subprocess.DEVNULL)
    else:
        shutil.copy2(os.path.join(src, name), dst)
    fix_text(dst)
    if name == 'imports/images.nss':
        shutil.copy2(dst, os.path.join(en, name))   # icons only, no text
    else:
        subprocess.run(py + [os.path.join(here, 'i18n', 'translate.py'), dst, os.path.join(en, name)], check=True)

os.makedirs(os.path.join(pkg, 'setup'))
shutil.copy2(os.path.join(here, 'install.ps1'), os.path.join(pkg, 'setup'))
cmd = ('@echo off\r\n'
       'rem Installs the Nilesoft Shell context menu preset (asks for administrator rights)\r\n'
       'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup' + chr(92) + 'install.ps1"\r\n')
open(os.path.join(pkg, 'Install.cmd'), 'w', encoding='ascii', newline='').write(cmd)

dev = os.path.join(pkg, 'dev')
os.makedirs(os.path.join(dev, 'i18n'))
for name in ('build_ffmpeg_nss.py', 'ffmpeg.nss.tmpl', 'build_tools_nss.py', 'build_paths_nss.py',
             'build_package.py', 'nss_check.py'):
    shutil.copy2(os.path.join(here, name), dev)
    fix_text(os.path.join(dev, name))
for name in ('spans.py', 'en.py', 'en_scripts.py', 'translate.py'):
    shutil.copy2(os.path.join(here, 'i18n', name), os.path.join(dev, 'i18n'))

print('package built:', pkg)

"""Build the shareable preset (the GitHub repository folder) from the live Nilesoft Shell config.

Usage: python -I build_package.py <nilesoft dir> <package dir>

  config/ru  - shell.nss + the imported files (Russian, as in the live config) with an empty paths.nss;
               all themes from imports/themes/, shell.nss always imports the default one (DEFAULT_THEME)
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


BOM = bytes([0xEF, 0xBB, 0xBF])


def fix_text(path):
    """In the package the generators live in dev/, not in the author's own source folder."""
    raw = open(path, 'rb').read()
    bom = raw.startswith(b'\xef\xbb\xbf')
    t = raw.decode('utf-8-sig').replace('dev/', 'dev/')
    open(path, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + t.encode('utf-8'))


for sub in ('config', 'setup', 'dev'):
    shutil.rmtree(os.path.join(pkg, sub), ignore_errors=True)

ru = os.path.join(pkg, 'config', 'ru')
en = os.path.join(pkg, 'config', 'en')
os.makedirs(os.path.join(ru, 'imports', 'themes'))
os.makedirs(os.path.join(en, 'imports', 'themes'))

# The live config may use any theme; the package always starts with the default one
DEFAULT_THEME = 'acrylic'
THEME_LINE = r"^import\s+'imports/themes/[^']+\.nss'"
shell = open(os.path.join(src, 'shell.nss'), encoding='utf-8-sig').read()
imports = [n for n in re.findall(r"^import\s+'imports/([^']+)'", shell, re.M) if not n.startswith('themes/')]
themes = sorted('themes/' + n for n in os.listdir(os.path.join(src, 'imports', 'themes')) if n.endswith('.nss'))
names = ['shell.nss'] + ['imports/' + n for n in imports + themes + ['ffmpeg-run.ps1', 'tools-run.ps1']]
for name in names:
    dst = os.path.join(ru, name)
    if name == 'imports/paths.nss':
        # Users edit this file by hand, so the generator writes its comments in each language itself
        for lang, folder in (('ru', ru), ('en', en)):
            subprocess.run(py + [os.path.join(here, 'build_paths_nss.py'), os.path.join(folder, name), '--lang', lang],
                           check=True, stdout=subprocess.DEVNULL)
        continue
    shutil.copy2(os.path.join(src, name), dst)
    fix_text(dst)
    if name == 'shell.nss':
        raw = open(dst, 'rb').read()
        text, n = re.subn(THEME_LINE, f"import 'imports/themes/{DEFAULT_THEME}.nss'", raw.decode('utf-8-sig'), flags=re.M)
        assert n == 1, 'shell.nss: no theme import line'
        open(dst, 'wb').write(raw[:3] * raw.startswith(BOM) + text.encode('utf-8'))
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

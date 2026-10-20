"""Build imports/tools.nss and the smart-select block for imports/file-manage.nss.

Usage: python -I build_tools_nss.py <tools.nss out> <select block out>

Glyph icons are written as tokens like U+E239 and turned into Nilesoft escapes here,
and BS stands for a backslash, so no backslashes pass through tools that might
treat them as escapes. Menu items only call imports/tools-run.ps1.
"""
import re
import sys

tools_out, select_out = sys.argv[1], sys.argv[2]
BSL = chr(92)


def esc(text):
    text = re.sub(r'U\+([0-9A-F]{4})', lambda m: BSL + 'u' + m.group(1), text)
    return text.replace('BS', BSL)


def run(action, value='', files=True, hidden=False):
    """args for an item that calls tools-run.ps1."""
    head = '@tools_hidden' if hidden else '@tools_run'
    a = f'{head} -Action {action}'
    if value:
        a += f' -Value {value}'
    if files:
        a += ' @sel(true," ")'
    return a


def item(title, action, value='', tip='', extra='', image='', files=True, hidden=False):
    attrs = f"title='{title}'"
    if extra:
        attrs = extra + ' ' + attrs
    if image:
        attrs += f' image={image}'
    line = [f"item({attrs}"]
    if tip:
        line.append(f"\ttip='{tip}'")
    win = " window='hidden'" if hidden else ''
    line.append(f"\tcmd='powershell.exe' args='{run(action, value, files, hidden)}'{win})")
    return line


def raw_item(title, cmd, tip='', extra='', image=''):
    attrs = f"title='{title}'"
    if extra:
        attrs = extra + ' ' + attrs
    if image:
        attrs += f' image={image}'
    line = [f'item({attrs}']
    if tip:
        line.append(f"\ttip='{tip}'")
    line.append(f'\t{cmd})')
    return line


def menu(title, children, extra='', tip='', image=''):
    attrs = f"title='{title}'"
    if extra:
        attrs = extra + ' ' + attrs
    if image:
        attrs += f' image={image}'
    if tip:
        attrs += f" tip='{tip}'"
    out = [f'menu({attrs})', '{']
    for c in children:
        out += ['\t' + l for l in c]
    return out + ['}']


SEP = ['separator()']

# ---------- Tools ----------
hash_menu = menu('Хэш (контрольная сумма)', [
    item('Показать MD5, SHA-1, SHA-256', 'hash-show', extra="type='file'", tip='Можно сразу скопировать нужный клавишей 1, 2 или 3'),
    menu('Скопировать', [
        item('MD5', 'hash-copy', 'MD5'),
        item('SHA-1', 'hash-copy', 'SHA1'),
        item('SHA-256', 'hash-copy', 'SHA256'),
    ], extra="mode='single' type='file'"),
    item('Сверить с эталоном…', 'hash-verify', extra="mode='single' type='file'",
         tip='Скопируй хэш с сайта — он возьмётся из буфера сам. Тип хэша определяется по длине'),
    item('Сравнить два файла', 'hash-compare', extra="type='file' where=sel.count==2", tip='Одинаковые ли файлы по содержимому (SHA-256)'),
    SEP,
    item('Создать файл контрольных сумм (SHA-256)', 'hash-create', tip='checksums.sha256 рядом: по нему потом можно проверить, что файлы не испортились'),
    item('Проверить по файлу контрольных сумм', 'hash-check', extra="mode='single' type='file' find='.md5|.sha1|.sha256|.sha384|.sha512'",
         tip='Проверит каждый файл из списка: целый, повреждён или пропал'),
], extra="mode='multiple' type='file|dir'", image='U+E239')

rename_menu = menu('Переименовать', [
    item('строчные буквы', 'rename-run', 'lower'),
    item('ЗАГЛАВНЫЕ БУКВЫ', 'rename-run', 'upper'),
    item('Как в предложении', 'rename-run', 'sentence'),
    item('Каждое Слово С Большой', 'rename-run', 'title'),
    SEP,
    item('Убрать лишние пробелы', 'rename-run', 'spaces'),
    item('Пробелы → подчёркивания', 'rename-run', 'space2under'),
    item('Подчёркивания → пробелы', 'rename-run', 'under2space'),
    item('Точки → пробелы', 'rename-run', 'dot2space', tip='Для имён вроде Movie.2024.1080p'),
    SEP,
    item('Добавить в начало…', 'rename-run', 'prefix'),
    item('Добавить в конец…', 'rename-run', 'suffix'),
    item('Найти и заменить…', 'rename-run', 'replace', tip='Без учёта регистра. Формат ввода: что|на что'),
    item('Пронумеровать…', 'rename-run', 'number', tip='Общее имя и номера по порядку: «Отпуск 01», «Отпуск 02»…'),
    item('Сменить расширение…', 'rename-run', 'ext', extra="type='file'"),
    SEP,
    item('Отменить последнее переименование', 'rename-undo', files=False),
], extra="mode='multiple' type='file|dir'", image='icon.rename',
   tip='Сначала покажет, что получится, и спросит подтверждение')

upload_menu = menu('Поделиться ссылкой', [
    item('temp.sh — на 3 дня, до 4 ГБ', 'upload', 'tempsh', tip='Файл загрузится на temp.sh, ссылка скопируется в буфер'),
    item('uguu.se — на 3 часа, до 128 МБ', 'upload', 'uguu', tip='Файл загрузится на uguu.se, ссылка скопируется в буфер'),
], extra="mode='single' type='file'", image='U+E14A',
   tip='Файл уходит на чужой сервер — не загружай личное')

image_menu = menu('Образ диска', [
    item('Подключить и открыть', 'iso-mount', image='icon.mount'),
    item('Отключить', 'iso-unmount', image='icon.eject'),
], extra="mode='single' type='file' find='.iso|.img'", image='icon.mount')

tools = menu('Инструменты', [hash_menu, rename_menu, upload_menu, image_menu],
             extra="mode='multiple' type='file|dir'", image='icon.settings')

# ---------- Everything ----------
def ev(title, value, tip='', extra=''):
    return item(title, 'everything', value, tip=tip, extra=extra, hidden=True)


everything = menu('Найти в Everything', [
    ev('В этой папке', 'here'),
    ev('По всему диску', 'drive'),
    SEP,
    menu('В этой папке только', [
        ev('Видео', 'video'), ev('Картинки', 'pic'), ev('Музыка', 'audio'), ev('Документы', 'doc'),
        ev('Архивы', 'zip'), ev('Программы', 'exe'), ev('Папки', 'folder'),
    ]),
    menu('Большие файлы', [
        ev('В этой папке больше 100 МБ', 'big100'),
        ev('В этой папке больше 1 ГБ', 'big1g'),
        ev('На всех дисках больше 1 ГБ', 'big1gall'),
    ]),
    ev('Изменённые сегодня', 'today'),
    ev('Изменённые за неделю', 'week'),
    SEP,
    ev('С таким же расширением здесь', 'sameext', extra="type='file'"),
    ev('С таким же расширением везде', 'sameextall', extra="type='file'"),
    ev('С таким же именем везде', 'samename', extra="type='file'", tip='Найдёт копии этого файла на всех дисках'),
], extra="mode='single' type='file|dir|back.dir|drive|back.drive' where=path.exists(ev_exe)", image='ev_exe')

# ---------- Drive maintenance ----------
drive = menu('Обслуживание диска', [
    raw_item('Очистка диска', "cmd='cleanmgr.exe' args='/d @str.left(sel.root, 1)'", image='U+E0CE',
             tip='Удалить временные файлы, кэш обновлений и прочий мусор'),
    raw_item('Оптимизация (дефрагментация / TRIM)', "cmd='dfrgui.exe'", image='U+E25C',
             tip='Для SSD Windows делает TRIM, для HDD — дефрагментацию'),
    raw_item('Проверить на ошибки', "admin cmd='cmd.exe' args='/c chkdsk @str.left(sel.root, 2) /scan & echo. & pause'", image='U+E0F6',
             tip='Быстрая проверка файловой системы без перезагрузки. Нужны права администратора'),
    SEP,
    raw_item('Управление дисками', "cmd='diskmgmt.msc'", image='icon.settings'),
], extra="type='drive'", image='U+E253')

eject = item('Извлечь подключённый образ', 'iso-eject', '@str.left(sel.root, 1)', extra="type='dvd'", image='icon.eject',
             tip='Для дисков, подключённых из ISO/IMG', files=False)

# ---------- Power ----------
def pw(title, value, image, tip=''):
    return item(title, 'power', value, tip=tip, image=image, files=False, hidden=True)


power = menu('Питание', [
    raw_item('Заблокировать', "cmd='rundll32.exe' args='user32.dll,LockWorkStation'", image='U+E100', extra="keys='Win+L'"),
    pw('Сон', 'sleep', 'U+E11C'),
    item('Гибернация', 'power', 'hibernate', image='U+E017', files=False, hidden=True,
         extra="where=reg.get('HKLMBSSYSTEMBSCurrentControlSetBSControlBSPower', 'HibernateEnabled') == 1",
         tip='Сохраняет всё на диск и полностью выключает компьютер'),
    SEP,
    pw('Перезагрузка', 'restart', 'U+E025', tip='Спросит подтверждение'),
    pw('Выключение', 'shutdown', 'U+E12F', tip='Спросит подтверждение'),
    menu('Выключить по таймеру', [
        pw('Через 15 минут', 'timer-15', 'U+E129'),
        pw('Через 30 минут', 'timer-30', 'U+E129'),
        pw('Через 1 час', 'timer-60', 'U+E129'),
        pw('Через 1,5 часа', 'timer-90', 'U+E129'),
        pw('Через 2 часа', 'timer-120', 'U+E129'),
        pw('Через 3 часа', 'timer-180', 'U+E129'),
        SEP,
        pw('Отменить таймер', 'timer-cancel', 'U+E0CE'),
    ], image='U+E129', tip='Windows покажет уведомление о запланированном выключении'),
    SEP,
    pw('Перезагрузить в BIOS/UEFI', 'bios', 'U+E1A9', tip='Спросит подтверждение и права администратора'),
    pw('Особые варианты загрузки', 'advanced', 'U+E0F6', tip='Восстановление, безопасный режим, загрузка с флешки'),
    pw('Выйти из учётной записи', 'logoff', 'U+E102', tip='Спросит подтверждение'),
], extra="type='desktop|taskbar'", image='U+E14D')

header = """// Tools based on the RubicBG library (github.com/RubicBG/Nilesoft-Shell-Snippets), rewritten
// for Nilesoft 1.9.18. All the work happens in imports/tools-run.ps1.
// This file is generated by build_tools_nss.py - better edit that script.

// The path to Everything ($ev_exe) is set in imports/paths.nss
$tools_ps     = path.combine(app.dir, 'imports', 'tools-run.ps1')
$tools_run    = '-NoProfile -ExecutionPolicy Bypass -File "' + tools_ps + '" -Everything "' + ev_exe + '"'
$tools_hidden = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + tools_ps + '" -Everything "' + ev_exe + '"'
"""

body = [header]
for block in (tools, everything, drive, eject, power):
    body += block + ['']
text = esc('\n'.join(body))
open(tools_out, 'w', encoding='utf-8', newline='\r\n').write(text)

# ---------- Smart select (inserted into "File manage > Select") ----------
def sel(title, value, extra=''):
    return item(title, 'select', value, extra=extra, files=(value == 'sameext'), hidden=True) \
        if value != 'sameext' else item(title, 'select', value, extra=extra, hidden=True)


def with_hwnd(lines):
    # -Folder gets a trailing "BS.": "D:BS." instead of "D:BS", otherwise the backslash eats the closing quote
    return [l.replace(' -Action select', ' -Hwnd @wnd.handle -Folder "@sel.dirBS." -Action select') for l in lines]


select_block = []
select_block += SEP
select_block += with_hwnd(menu('По типу', [
    sel('Видео', 'video'), sel('Картинки', 'image'), sel('Музыка', 'audio'), sel('Документы', 'doc'), sel('Архивы', 'archive'),
    SEP, sel('Только папки', 'folders'), sel('Только файлы', 'files'),
]))
select_block += with_hwnd(menu('По размеру', [sel('Больше 100 МБ', 'big100'), sel('Больше 1 ГБ', 'big1g'), sel('Пустые файлы', 'empty')]))
select_block += with_hwnd(menu('По дате изменения', [sel('Сегодня', 'today'), sel('За неделю', 'week'), sel('Старше полугода', 'old')]))
select_block += with_hwnd(sel('С таким же расширением', 'sameext', extra="mode='single' type='file'"))
select_block += with_hwnd(sel('По маске…', 'mask'))
open(select_out, 'w', encoding='utf-8', newline='\r\n').write(esc('\n'.join(select_block)))
print('written', tools_out, 'and', select_out)

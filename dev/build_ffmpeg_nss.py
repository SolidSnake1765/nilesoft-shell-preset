"""Build imports/ffmpeg.nss from ffmpeg.nss.tmpl.

Usage: python -I build_ffmpeg_nss.py <template> <output>

Menu items only call ffmpeg-run.ps1 with a preset name (and value); the ffmpeg
arguments themselves live in that script. The template uses the token BS for a
backslash, so no backslashes pass through tools that might treat them as escapes.
"""
import sys

tmpl_path, out_path = sys.argv[1], sys.argv[2]
SEP = 'separator'
# "On the graphics card" items are shown when the check found a GPU encoder (ffmpeg-run.ps1 writes GpuEnc
# to the registry). Before the first check: when an NVIDIA or AMD driver is present ($has_gpu_hint from paths.nss)
GPU = ("if(reg.get(ff_key, 'GpuEnc') == 'nvenc' or reg.get(ff_key, 'GpuEnc') == 'amf' or reg.get(ff_key, 'GpuEnc') == 'qsv', true, "
       "if(reg.get(ff_key, 'GpuEnc') == 'none', false, has_gpu_hint))")


def item(title, preset, value='', tip='', find='', where=''):
    return ('item', title, preset, value, tip, find, where)


def menu(title, children, find='', tip='', where=''):
    return ('menu', title, children, find, tip, where)


def section(find, children):
    """Untitled expanded menu: its items show inline only for matching files."""
    return ('section', find, children)


def render(node, indent):
    if node == SEP:
        return [indent + 'separator()']
    kind = node[0]
    if kind == 'item':
        _, title, preset, value, tip, find, where = node
        args = '@ff_run -Preset ' + preset + (' -Value ' + value if value else '') + ' @sel(true," ")'
        attrs = "mode='multiple'" + (f" find='{find}'" if find else '') + (f' where={where}' if where else '') + f" title='{title}'"
        lines = [f'{indent}item({attrs}']
        if tip:
            lines.append(f"{indent}\ttip='{tip}'")
        lines.append(f"{indent}\tcmd='powershell.exe' args='{args}')")
        return lines
    if kind == 'menu':
        _, title, children, find, tip, where = node
        attrs = "mode='multiple'" + (f' find={find}' if find else '') + (f' where={where}' if where else '') + f" title='{title}'" + (f" tip='{tip}'" if tip else '')
        lines = [f'{indent}menu({attrs})', indent + '{']
        for c in children:
            lines += render(c, indent + '\t')
        return lines + [indent + '}']
    if kind == 'section':
        _, find, children = node
        lines = [f"{indent}menu(mode='multiple' expanded=1 find={find})", indent + '{']
        for c in children:
            lines += render(c, indent + '\t')
        return lines + [indent + '}']
    raise ValueError(node)


def volume(prefix):
    louder = menu('Громче', [item(f'+{d} дБ', 'louder', d) for d in ('3', '6', '10')],
                  tip='+6 дБ — примерно вдвое громче по амплитуде')
    quieter = menu('Тише', [item(f'-{d} дБ', 'quieter', d) for d in ('3', '6', '10')])
    norm = item('Выровнять громкость', 'normalize', tip='Привести к стандартной громкости (EBU R128, -16 LUFS)')
    return [louder, quieter, norm]


rotate_items = lambda preset: [
    item('На 90° вправо', preset, 'right'),
    item('На 90° влево', preset, 'left'),
    item('На 180°', preset, '180'),
    SEP,
    item('Отразить по горизонтали', preset, 'hflip'),
    item('Отразить по вертикали', preset, 'vflip'),
]

MULTI = 'sel.count>1'   # "Join" is shown only when several files are selected

speed_items = [item(f'{s}×', 'speed', s) for s in ('0.5', '0.75', '1.25', '1.5', '2')]

H265_DISCORD = 'Чётче при том же размере. Discord его поддерживает, но на старых компьютерах встроенный плеер может не показать видео'
H265_WEB = 'Чётче при том же размере, но не все браузеры (например Firefox) показывают H.265'


def fit_items(target, h265_tip):
    """Discord/Catbox presets: the script picks resolution and fps for the video length."""
    return [
        item('Авто — баланс', 'fit', f'{target}:auto:h264', tip='Сам подбирает разрешение и частоту кадров под длину видео'),
        item('Плавность — 60 fps', 'fit', f'{target}:smooth:h264', tip='Для игр: держит 60 кадров, жертвуя разрешением'),
        item('Чёткость — 30 fps', 'fit', f'{target}:sharp:h264', tip='Для разговоров и записи экрана: 30 кадров, зато разрешение выше'),
        SEP,
        item('Авто, H.265 — лучше качество', 'fit', f'{target}:auto:h265', tip=h265_tip),
    ]


video = section('ff_video', [
    menu('В MP4 без потери качества', [
        item('Автоматически (для Telegram)', 'hq', 'auto',
             tip='Видео H.264 копируется как есть, без потерь и мгновенно. Перекодируется только то, что не подходит для MP4'),
        SEP,
        item('H.264 на процессоре', 'hq', 'h264', tip='Визуально без потерь (CRF 17). Открывается везде'),
        item('H.264 на видеокарте', 'hq', 'h264gpu', where=GPU, tip='Визуально без потерь, в разы быстрее. Файл больше, чем на процессоре'),
        item('H.265 на процессоре', 'hq', 'h265', tip='Визуально без потерь, файл меньше. Не все клиенты Telegram его показывают'),
        item('H.265 на видеокарте', 'hq', 'h265gpu', where=GPU, tip='Визуально без потерь, быстро. Не все клиенты Telegram его показывают'),
    ], tip='Для файлов, которые Telegram и телефоны не принимают как видео'),
    menu('Сжать', [
        item('H.264 (совместимо со всем)', 'compress', tip='Заметно меньше размер при хорошем качестве'),
        item('H.265 (ещё меньше, дольше)', 'h265', tip='Меньше размер при том же качестве, но кодирует дольше'),
        item('На видеокарте (H.265, быстро)', 'gpu265', where=GPU, tip='Во много раз быстрее, файл немного больше'),
    ]),
    menu('Ужать под лимит', [
        menu('Discord — 20 МБ', fit_items('discord20', H265_DISCORD)),
        menu('Discord — 10 МБ (старый лимит)', fit_items('discord10', H265_DISCORD)),
        menu('Catbox — 200 МБ', fit_items('catbox', H265_WEB)),
        SEP,
        menu('Свой размер…', fit_items('custom', H265_WEB), tip='Спросит, сколько мегабайт должен весить результат'),
    ], tip='Любое видео гарантированно влезет в лимит: разрешение и частота кадров подбираются под его длину'),
    menu('Уменьшить', [item(f'До {h}p', 'height', h, tip='Пропорции сохраняются, меньшее видео не увеличивается') for h in ('1080', '720', '480')]),
    menu('Обрезать', [
        item('Быстро, без перекодирования…', 'trim', tip='Спросит начало и конец. Мгновенно, но режет по ближайшим ключевым кадрам'),
        item('Точно, с перекодированием…', 'trim-exact', tip='Спросит начало и конец. Режет ровно по указанному времени'),
    ]),
    menu('Скорость', speed_items, tip='Звук ускоряется вместе с видео, высота голоса не меняется'),
    menu('Частота кадров', [item(f'{f} fps', 'fps', f) for f in ('30', '60')],
         tip='60 из 30 не делает движение плавнее — кадры просто повторяются'),
    menu('Повернуть', [
        menu('Мгновенно, без перекодирования', [
            item('На 90° вправо', 'lrotate', 'right'),
            item('На 90° влево', 'lrotate', 'left'),
            item('На 180°', 'lrotate', '180'),
        ], find="'.mp4|.mov|.m4v'", tip='Меняется только метка поворота — без потерь. Для роликов с телефона, которые показываются боком'),
        SEP,
    ] + rotate_items('vrotate'), tip='Обычные пункты перекодируют видео в MP4 (H.264 высокого качества)'),
    menu('Улучшить', [
        item('Стабилизировать (убрать тряску)', 'stab', tip='Два прохода: анализ движения и выравнивание. Края слегка обрезаются'),
        item('Убрать шум', 'denoise', tip='Для тёмных и зернистых видео с телефона'),
        item('Добавить резкость', 'sharpen', tip='Подчёркивает детали, если видео выглядит мыльным'),
        item('Убрать чёрные полосы', 'crop', tip='Сам находит полосы сверху/снизу/по бокам и обрезает их'),
        item('Убрать «гребёнку» (чересстрочность)', 'deint', tip='Для старых записей с камер и ТВ'),
        item('Плавность 60 fps (дорисовка кадров)', 'interp', tip='Дорисовывает промежуточные кадры. Очень медленно — для коротких роликов'),
    ], tip='Все пункты перекодируют видео в MP4'),
    menu('Перепаковать без перекодирования', [
        item('В MP4', 'remux-mp4', tip='Мгновенно и без потерь. Не сработает, если кодеки не подходят для MP4'),
        item('В MKV', 'remux-mkv', tip='Мгновенно и без потерь, все дорожки и субтитры сохраняются'),
    ]),
    item('Склеить выбранные в один файл', 'concat', where=MULTI,
         tip='По алфавиту, без перекодирования. Файлы должны быть с одинаковыми параметрами (например, части одной записи)'),
    item('Разрезать на части…', 'split', tip='Спросит, по сколько минут. Без перекодирования'),
    item('Удалить метаданные (GPS, камера, даты)', 'stripmeta', tip='Перед тем как выложить видео с телефона. Без перекодирования'),
    menu('Субтитры', [
        item('Извлечь все в отдельные файлы', 'subs-extract', tip='SRT, ASS, VTT, SUP — рядом с видео'),
        item('Добавить файл, лежащий рядом', 'subs-add', tip='Берёт «имя.srt» или «имя.ru.srt» (.ass, .vtt) и добавляет дорожкой в MKV, включаемой в плеере'),
        item('Вшить в картинку', 'subs-burn', tip='Субтитры навсегда в кадре — видны везде. Берёт файл рядом или встроенные субтитры'),
    ]),
    SEP,
    menu('Звук', [
        menu('Извлечь', [
            item('MP3 (320 кбит/с)', 'extract', 'mp3'),
            item('M4A (AAC 256 кбит/с)', 'extract', 'm4a'),
            item('AAC (256 кбит/с)', 'extract', 'aac'),
            item('OPUS (160 кбит/с)', 'extract', 'opus'),
            item('OGG (Vorbis)', 'extract', 'ogg'),
            item('FLAC (без потерь)', 'extract', 'flac'),
            item('WAV', 'extract', 'wav'),
            item('AIFF', 'extract', 'aiff'),
            SEP,
            item('Как есть, без перекодирования (MKA)', 'extract', 'mka', tip='Дорожка без изменений. MKA открывают AIMP, VLC и MPC-HC'),
        ], tip='Всегда создаёт новый файл, видео не трогается'),
        item('Убрать звук', 'mute', tip='Копия видео без звуковой дорожки, без перекодирования'),
        item('Выбрать звуковую дорожку…', 'pickaudio', tip='Покажет список дорожек с языками и оставит одну. Без перекодирования'),
        item('Убрать шум из голоса', 'voice', tip='Шумоподавление и срез гула. Видео не перекодируется'),
        SEP,
    ] + volume('video')),
    menu('Создать из видео', [
        menu('GIF', [
            item('Маленький (320 px, 10 к/с, 64 цвета)', 'gif', '1', tip='Самый лёгкий файл — для мессенджеров'),
            item('Средний (400 px, 12 к/с)', 'gif', '2', tip='Баланс размера и качества'),
            item('Качественный (480 px, 15 к/с)', 'gif', '3', tip='Лучшие цвета и плавность, файл больше'),
        ]),
        item('Вертикальное 9:16 (Shorts, TikTok, Reels)', 'vertical', tip='1080×1920: видео по центру на размытом фоне'),
        item('Кадр из середины (JPG)', 'frame'),
        item('Превью-сетка 4×4 (JPG)', 'sheet', tip='16 кадров с равным шагом по всему видео на одной картинке'),
        item('Задом наперёд', 'reverse', tip='Для коротких роликов: длинное видео займёт много памяти'),
        SEP,
        item('Кадры каждые N секунд в папку…', 'frames', tip='Спросит интервал и сохранит JPG в отдельную папку'),
        item('Нарезка-превью (6 фрагментов по 2 с)', 'teaser', tip='Короткий ролик из кусочков по всему видео — показать, о чём оно'),
    ], tip='Всегда создаёт новый файл, видео не трогается'),
])

audio = section('ff_audio', [
    menu('Конвертировать', [
        item('В MP3 (320 кбит/с)', 'audio', 'mp3', find='!.mp3'),
        item('В MP3 (VBR, около 190 кбит/с)', 'audio', 'mp3vbr', tip='Почти то же качество, файл меньше'),
        item('В M4A (AAC 256 кбит/с)', 'audio', 'm4a', find='!.m4a'),
        item('В OPUS (160 кбит/с)', 'audio', 'opus', find='!.opus', tip='Самый современный кодек: лучшее качество на килобайт'),
        item('В OGG (Vorbis)', 'audio', 'ogg', find='!.ogg'),
        item('В FLAC (без потерь)', 'audio', 'flac', find='!.flac'),
        item('В WAV', 'audio', 'wav', find='!.wav'),
        item('В AIFF', 'audio', 'aiff', find='!.aiff'),
    ]),
] + volume('audio') + [
    item('Убрать тишину в начале и в конце', 'silence', tip='Отрезает тишину тише -50 дБ по краям'),
    item('Обрезать…', 'trim', tip='Спросит начало и конец, без перекодирования'),
    menu('Скорость', speed_items, tip='Высота голоса не меняется'),
    item('Склеить выбранные в один файл', 'concat', where=MULTI, tip='По алфавиту, без перекодирования. Файлы должны быть одного формата'),
    item('Разрезать на части…', 'split', tip='Спросит, по сколько минут. Без перекодирования'),
    item('Убрать шум из голоса', 'voice', tip='Для записей голоса, подкастов и диктофона'),
    SEP,
    item('Сделать видео (обложка или волна)', 'musicvideo', tip='Для YouTube и Telegram: картинка — обложка из файла, а если её нет — волна звука'),
    item('Спектрограмма (PNG)', 'spectrum', tip='Видно настоящее качество: у «раздутого» из MP3 FLAC всё выше 16 кГц срезано'),
    item('Удалить метаданные', 'stripmeta', tip='Теги, обложка остаются в потоке. Без перекодирования'),
])

image = section('ff_image', [
    menu('Конвертировать', [
        item('В JPG', 'image', 'jpg', find='!.jpg'),
        item('В PNG', 'image', 'png', find='!.png', tip='Без потерь'),
        item('В WebP (качество 90)', 'image', 'webp', find='!.webp', tip='Меньше JPG при том же качестве'),
        item('В AVIF', 'image', 'avif', find='!.avif', tip='Самый компактный формат, открывается в новых браузерах и Windows 11'),
        SEP,
        item('В иконку ICO (256×256)', 'ico', tip='Картинка вписывается в квадрат, по краям прозрачные поля'),
        item('Сжать для сайтов (WebP, до 2560 px)', 'web', tip='Для блогов, форумов и сайтов: маленький файл, хорошее качество'),
    ]),
    menu('Увеличить', [item(f'×{k}', 'upscale', str(k)) for k in range(2, 11)],
         tip='Простое увеличение (lanczos): картинка больше, но новых деталей не появится'),
    menu('Уменьшить', [item(f'В {k} раза', 'downscale', str(k)) for k in (2, 3, 4)]),
    menu('Повернуть', rotate_items('irotate')),
    item('Чёрно-белое', 'gray'),
    item('Слайд-шоу из выбранных (MP4)', 'slideshow', where=MULTI, tip='По алфавиту, 1920×1080. Спросит, сколько секунд показывать каждую'),
])


def toggle(title, name, on, off, tip, where=''):
    """Settings item with a checkmark; click flips the registry value between on and off."""
    cur = f"reg.get(ff_key, '{name}')"
    return [
        f"\t\titem(mode='multiple'" + (f' where={where}' if where else '') + f" title='{title}' checked=if({cur} == '{on}', true, false)",
        f"\t\t\ttip='{tip}'",
        f"\t\t\tcmd=reg.set(ff_key, '{name}', if({cur} == '{on}', '{off}', '{on}'), reg.sz))",
    ]


settings = ["\tmenu(mode='multiple' title='Настройки')", '\t{']
settings += toggle('Сохранять копии в подпапку «FFmpeg»', 'OutDir', 'sub', 'here',
                   'Выключено — результаты кладутся рядом с исходником')
settings += toggle('Кодировать видео на видеокарте', 'Encoder', 'gpu', 'cpu',
                   'NVIDIA, AMD или Intel: в разы быстрее, файл чуть больше. Выключено — процессор (x264), лучше качество на мегабайт', where=GPU)
settings += toggle('Всегда ждать Enter в конце', 'Window', 'wait', 'auto',
                   'Выключено — после успешной обработки окно закрывается само через 3 секунды')
settings += toggle('Звуковой сигнал по окончании', 'Beep', 'on', 'off',
                   'Полезно для долгой обработки: можно заниматься своими делами')
settings += toggle('Показать результат в проводнике', 'Reveal', 'on', 'off',
                   'После обработки откроется папка с выделенным результатом')
settings += [
    "\t\titem(mode='multiple' title='Проверить видеокарту'",
    "\t\t\ttip='Умеет ли видеокарта кодировать видео (NVIDIA, AMD, Intel). Нужно после замены видеокарты или драйвера'",
    "\t\t\tcmd='powershell.exe' args='@ff_run -Preset gpu-detect')",
]
settings += ['\t}']

body = []
body += [
    '\t// Mode switch: copy / replace',
    "\titem(mode='multiple' title=if(reg.get(ff_key, 'Mode') == 'replace', 'Режим: замена', 'Режим: копия')",
    "\t\ttip=if(reg.get(ff_key, 'Mode') == 'replace', 'Исходник после обработки уходит в Корзину, результат получает его имя. Нажми, чтобы включить копию', 'Результат сохраняется рядом, исходник не трогается. Нажми, чтобы включить замену')",
    "\t\tcmd=reg.set(ff_key, 'Mode', if(reg.get(ff_key, 'Mode') == 'replace', 'copy', 'replace'), reg.sz))",
]
body += settings + ['\tseparator()']
for sec in (video, audio, image):
    body += render(sec, '\t')
body += ['\tseparator()', '\t// Info']
pair = menu('Видео + музыка', [
    item('Заменить звук музыкой', 'addaudio', 'replace', tip='Звук видео заменяется выбранным файлом; короткая музыка повторяется по кругу'),
    item('Добавить музыку фоном', 'addaudio', 'mix', tip='Музыка тише и звучит поверх родного звука видео; короткая повторяется по кругу'),
], where='sel.count==2', tip='Выдели одно видео и один аудиофайл')
body += render(pair, '\t')
body += render(section("ff_video+'|'+ff_audio", [item('Проверить на ошибки', 'check', tip='Полное декодирование: покажет, есть ли в файле битые места')]), '\t')
body += [
    "\titem(mode='multiple' title='Сведения о файле' tip='Кодеки, разрешение, длительность, битрейт'",
    '\t\tcmd-line=`/c (for %f in (@(sel(true," "))) do (echo. & "@ff_probe" -hide_banner "%~f")) & echo. & pause`)',
    "\titem(mode='single' find=ff_video+'|'+ff_audio title='Воспроизвести в ffplay' tip='Пробел — пауза, Esc — закрыть'",
    "\t\tcmd=ff_play args='-hide_banner \"@sel.path\"')",
    "\titem(mode='multiple' title='Версия FFmpeg' keys='Shift' vis=key.shift()",
    '\t\tcmd-line=`/c ("@ff_exe" -hide_banner -version) & pause`)',
]

bs = chr(92)
text = open(tmpl_path, encoding='utf-8').read()
text = text.replace('@@ITEMS@@', '\n'.join(body)).replace('BS', bs)
open(out_path, 'w', encoding='utf-8', newline='\r\n').write(text)
print('written', out_path, len(text.splitlines()), 'lines')

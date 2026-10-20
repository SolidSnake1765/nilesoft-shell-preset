// Инструменты из библиотеки RubicBG (github.com/RubicBG/Nilesoft-Shell-Snippets), переписанные
// под нашу версию Nilesoft 1.9.18 и на русском. Вся работа — в imports/tools-run.ps1.
// Файл собирается скриптом dev/build_tools_nss.py — правки лучше вносить туда.

// Путь к Everything ($ev_exe) задаётся в imports/paths.nss
$tools_ps     = path.combine(app.dir, 'imports', 'tools-run.ps1')
$tools_run    = '-NoProfile -ExecutionPolicy Bypass -File "' + tools_ps + '" -Everything "' + ev_exe + '"'
$tools_hidden = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + tools_ps + '" -Everything "' + ev_exe + '"'

menu(mode='multiple' type='file|dir' title='Инструменты' image=icon.settings)
{
	menu(mode='multiple' type='file|dir' title='Хэш (контрольная сумма)' image=\uE239)
	{
		item(type='file' title='Показать MD5, SHA-1, SHA-256'
			tip='Можно сразу скопировать нужный клавишей 1, 2 или 3'
			cmd='powershell.exe' args='@tools_run -Action hash-show @sel(true," ")')
		menu(mode='single' type='file' title='Скопировать')
		{
			item(title='MD5'
				cmd='powershell.exe' args='@tools_run -Action hash-copy -Value MD5 @sel(true," ")')
			item(title='SHA-1'
				cmd='powershell.exe' args='@tools_run -Action hash-copy -Value SHA1 @sel(true," ")')
			item(title='SHA-256'
				cmd='powershell.exe' args='@tools_run -Action hash-copy -Value SHA256 @sel(true," ")')
		}
		item(mode='single' type='file' title='Сверить с эталоном…'
			tip='Скопируй хэш с сайта — он возьмётся из буфера сам. Тип хэша определяется по длине'
			cmd='powershell.exe' args='@tools_run -Action hash-verify @sel(true," ")')
		item(type='file' where=sel.count==2 title='Сравнить два файла'
			tip='Одинаковые ли файлы по содержимому (SHA-256)'
			cmd='powershell.exe' args='@tools_run -Action hash-compare @sel(true," ")')
		separator()
		item(title='Создать файл контрольных сумм (SHA-256)'
			tip='checksums.sha256 рядом: по нему потом можно проверить, что файлы не испортились'
			cmd='powershell.exe' args='@tools_run -Action hash-create @sel(true," ")')
		item(mode='single' type='file' find='.md5|.sha1|.sha256|.sha384|.sha512' title='Проверить по файлу контрольных сумм'
			tip='Проверит каждый файл из списка: целый, повреждён или пропал'
			cmd='powershell.exe' args='@tools_run -Action hash-check @sel(true," ")')
	}
	menu(mode='multiple' type='file|dir' title='Переименовать' image=icon.rename tip='Сначала покажет, что получится, и спросит подтверждение')
	{
		item(title='строчные буквы'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value lower @sel(true," ")')
		item(title='ЗАГЛАВНЫЕ БУКВЫ'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value upper @sel(true," ")')
		item(title='Как в предложении'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value sentence @sel(true," ")')
		item(title='Каждое Слово С Большой'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value title @sel(true," ")')
		separator()
		item(title='Убрать лишние пробелы'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value spaces @sel(true," ")')
		item(title='Пробелы → подчёркивания'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value space2under @sel(true," ")')
		item(title='Подчёркивания → пробелы'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value under2space @sel(true," ")')
		item(title='Точки → пробелы'
			tip='Для имён вроде Movie.2024.1080p'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value dot2space @sel(true," ")')
		separator()
		item(title='Добавить в начало…'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value prefix @sel(true," ")')
		item(title='Добавить в конец…'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value suffix @sel(true," ")')
		item(title='Найти и заменить…'
			tip='Без учёта регистра. Формат ввода: что|на что'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value replace @sel(true," ")')
		item(title='Пронумеровать…'
			tip='Общее имя и номера по порядку: «Отпуск 01», «Отпуск 02»…'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value number @sel(true," ")')
		item(type='file' title='Сменить расширение…'
			cmd='powershell.exe' args='@tools_run -Action rename-run -Value ext @sel(true," ")')
		separator()
		item(title='Отменить последнее переименование'
			cmd='powershell.exe' args='@tools_run -Action rename-undo')
	}
	menu(mode='single' type='file' title='Поделиться ссылкой' image=\uE14A tip='Файл уходит на чужой сервер — не загружай личное')
	{
		item(title='temp.sh — на 3 дня, до 4 ГБ'
			tip='Файл загрузится на temp.sh, ссылка скопируется в буфер'
			cmd='powershell.exe' args='@tools_run -Action upload -Value tempsh @sel(true," ")')
		item(title='uguu.se — на 3 часа, до 128 МБ'
			tip='Файл загрузится на uguu.se, ссылка скопируется в буфер'
			cmd='powershell.exe' args='@tools_run -Action upload -Value uguu @sel(true," ")')
	}
	menu(mode='single' type='file' find='.iso|.img' title='Образ диска' image=icon.mount)
	{
		item(title='Подключить и открыть' image=icon.mount
			cmd='powershell.exe' args='@tools_run -Action iso-mount @sel(true," ")')
		item(title='Отключить' image=icon.eject
			cmd='powershell.exe' args='@tools_run -Action iso-unmount @sel(true," ")')
	}
}

menu(mode='single' type='file|dir|back.dir|drive|back.drive' where=path.exists(ev_exe) title='Найти в Everything' image=ev_exe)
{
	item(title='В этой папке'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value here @sel(true," ")' window='hidden')
	item(title='По всему диску'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value drive @sel(true," ")' window='hidden')
	separator()
	menu(title='В этой папке только')
	{
		item(title='Видео'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value video @sel(true," ")' window='hidden')
		item(title='Картинки'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value pic @sel(true," ")' window='hidden')
		item(title='Музыка'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value audio @sel(true," ")' window='hidden')
		item(title='Документы'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value doc @sel(true," ")' window='hidden')
		item(title='Архивы'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value zip @sel(true," ")' window='hidden')
		item(title='Программы'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value exe @sel(true," ")' window='hidden')
		item(title='Папки'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value folder @sel(true," ")' window='hidden')
	}
	menu(title='Большие файлы')
	{
		item(title='В этой папке больше 100 МБ'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value big100 @sel(true," ")' window='hidden')
		item(title='В этой папке больше 1 ГБ'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value big1g @sel(true," ")' window='hidden')
		item(title='На всех дисках больше 1 ГБ'
			cmd='powershell.exe' args='@tools_hidden -Action everything -Value big1gall @sel(true," ")' window='hidden')
	}
	item(title='Изменённые сегодня'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value today @sel(true," ")' window='hidden')
	item(title='Изменённые за неделю'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value week @sel(true," ")' window='hidden')
	separator()
	item(type='file' title='С таким же расширением здесь'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value sameext @sel(true," ")' window='hidden')
	item(type='file' title='С таким же расширением везде'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value sameextall @sel(true," ")' window='hidden')
	item(type='file' title='С таким же именем везде'
		tip='Найдёт копии этого файла на всех дисках'
		cmd='powershell.exe' args='@tools_hidden -Action everything -Value samename @sel(true," ")' window='hidden')
}

menu(type='drive' title='Обслуживание диска' image=\uE253)
{
	item(title='Очистка диска' image=\uE0CE
		tip='Удалить временные файлы, кэш обновлений и прочий мусор'
		cmd='cleanmgr.exe' args='/d @str.left(sel.root, 1)')
	item(title='Оптимизация (дефрагментация / TRIM)' image=\uE25C
		tip='Для SSD Windows делает TRIM, для HDD — дефрагментацию'
		cmd='dfrgui.exe')
	item(title='Проверить на ошибки' image=\uE0F6
		tip='Быстрая проверка файловой системы без перезагрузки. Нужны права администратора'
		admin cmd='cmd.exe' args='/c chkdsk @str.left(sel.root, 2) /scan & echo. & pause')
	separator()
	item(title='Управление дисками' image=icon.settings
		cmd='diskmgmt.msc')
}

item(type='dvd' title='Извлечь подключённый образ' image=icon.eject
	tip='Для дисков, подключённых из ISO/IMG'
	cmd='powershell.exe' args='@tools_run -Action iso-eject -Value @str.left(sel.root, 1)')

menu(type='desktop|taskbar' title='Питание' image=\uE14D)
{
	item(keys='Win+L' title='Заблокировать' image=\uE100
		cmd='rundll32.exe' args='user32.dll,LockWorkStation')
	item(title='Сон' image=\uE11C
		cmd='powershell.exe' args='@tools_hidden -Action power -Value sleep' window='hidden')
	item(where=reg.get('HKLM\SYSTEM\CurrentControlSet\Control\Power', 'HibernateEnabled') == 1 title='Гибернация' image=\uE017
		tip='Сохраняет всё на диск и полностью выключает компьютер'
		cmd='powershell.exe' args='@tools_hidden -Action power -Value hibernate' window='hidden')
	separator()
	item(title='Перезагрузка' image=\uE025
		tip='Спросит подтверждение'
		cmd='powershell.exe' args='@tools_hidden -Action power -Value restart' window='hidden')
	item(title='Выключение' image=\uE12F
		tip='Спросит подтверждение'
		cmd='powershell.exe' args='@tools_hidden -Action power -Value shutdown' window='hidden')
	menu(title='Выключить по таймеру' image=\uE129 tip='Windows покажет уведомление о запланированном выключении')
	{
		item(title='Через 15 минут' image=\uE129
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-15' window='hidden')
		item(title='Через 30 минут' image=\uE129
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-30' window='hidden')
		item(title='Через 1 час' image=\uE129
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-60' window='hidden')
		item(title='Через 1,5 часа' image=\uE129
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-90' window='hidden')
		item(title='Через 2 часа' image=\uE129
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-120' window='hidden')
		item(title='Через 3 часа' image=\uE129
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-180' window='hidden')
		separator()
		item(title='Отменить таймер' image=\uE0CE
			cmd='powershell.exe' args='@tools_hidden -Action power -Value timer-cancel' window='hidden')
	}
	separator()
	item(title='Перезагрузить в BIOS/UEFI' image=\uE1A9
		tip='Спросит подтверждение и права администратора'
		cmd='powershell.exe' args='@tools_hidden -Action power -Value bios' window='hidden')
	item(title='Особые варианты загрузки' image=\uE0F6
		tip='Восстановление, безопасный режим, загрузка с флешки'
		cmd='powershell.exe' args='@tools_hidden -Action power -Value advanced' window='hidden')
	item(title='Выйти из учётной записи' image=\uE102
		tip='Спросит подтверждение'
		cmd='powershell.exe' args='@tools_hidden -Action power -Value logoff' window='hidden')
}

settings
{
	priority=1
	exclude.where = !process.is_explorer
	showdelay = 200
	// Options to allow modification of system items
	modify.remove.duplicate=1
	tip.enabled=true
}

// Тема: файлы лежат в imports/themes/ — поменяй имя файла или выбери тему в меню
// (Shift + правый клик по панели задач → Nilesoft Shell → Тема)
import 'imports/themes/acrylic.nss'
import 'imports/images.nss'
// Пути к ffmpeg, Everything и LosslessCut — до остальных импортов, они ими пользуются
import 'imports/paths.nss'

import 'imports/modify.nss'

menu(mode="multiple" title="Закрепить/открепить" image=icon.pin)
{
}

menu(mode="multiple" title=title.more_options image=icon.more_options)
{
}

// Rarely used app items get moved here by rules in imports/modify.nss
menu(mode="multiple" title="Программы" image=\uE254)
{
}

// Access items from Win 10 Tweaker get moved here by rules in imports/modify.nss
menu(mode="multiple" title="Доступ" image=\uE194)
{
}

import 'imports/terminal.nss'
import 'imports/tools.nss'
import 'imports/file-manage.nss'
import 'imports/develop.nss'
import 'imports/goto.nss'
import 'imports/taskbar.nss'
import 'imports/losslesscut.nss'
import 'imports/ffmpeg.nss'
import 'imports/app.WinRAR.nss'
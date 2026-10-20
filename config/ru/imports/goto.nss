menu(type='*' where=window.is_taskbar||sel.count mode=mode.multiple title=title.go_to sep=sep.both image=\uE14A)
{
	menu(title='Папки' image=\uE1F4)
	{
		item(title='Windows' image=inherit cmd=sys.dir)
		item(title='System32' image=inherit cmd=sys.bin)
		item(title='Program Files' image=inherit cmd=sys.prog)
		item(title='Program Files x86' image=inherit cmd=sys.prog32)
		item(title='ProgramData' image=inherit cmd=sys.programdata)
		item(title='Приложения' image=inherit cmd='shell:appsfolder')
		item(title='Пользователи' image=inherit cmd=sys.users)
		separator
		//item(title='@user.name@@@sys.name' vis=label)
		item(title='Рабочий стол' image=inherit cmd=user.desktop)
		item(title='Загрузки' image=inherit cmd=user.downloads)
		item(title='Изображения' image=inherit cmd=user.pictures)
		item(title='Документы' image=inherit cmd=user.documents)
		item(title='Меню «Пуск»' image=inherit cmd=user.startmenu)
		item(title='Профиль' image=inherit cmd=user.dir)
		item(title='AppData' image=inherit cmd=user.appdata)
		item(title='Временные файлы' image=inherit cmd=user.temp)
	}
	item(title=title.control_panel image=\uE0F3 cmd='shell:::{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}')
	item(title='Все элементы панели управления' image=\uE0F3 cmd='shell:::{ED7BA470-8E54-465E-825C-99712043E01C}')
	item(title=title.run image=\uE14B cmd='shell:::{2559a1f3-21d7-11d4-bdaf-00c04f60b9f0}')
	menu(where=sys.ver.major >= 10 title=title.settings sep=sep.before image=\uE0F3)
	{
		// https://docs.microsoft.com/en-us/windows/uwp/launch-resume/launch-settings-app
		item(title='Система' image=inherit cmd='ms-settings:')
		item(title='О системе' image=inherit cmd='ms-settings:about')
		item(title='Ваши данные' image=inherit cmd='ms-settings:yourinfo')
		item(title='Сведения о системе' image=inherit cmd-line='/K systeminfo')
		item(title='Поиск' cmd='search-ms:' image=inherit)
		item(title='USB' image=inherit cmd='ms-settings:usb')
		item(title='Центр обновления Windows' image=inherit cmd='ms-settings:windowsupdate')
		item(title='Безопасность Windows' image=inherit cmd='ms-settings:windowsdefender')
		menu(title='Приложения' image=inherit)
		{
			item(title='Установленные приложения' image=inherit cmd='ms-settings:appsfeatures')
			item(title='Приложения по умолчанию' image=inherit cmd='ms-settings:defaultapps')
			item(title='Дополнительные компоненты' image=inherit cmd='ms-settings:optionalfeatures')
			item(title='Автозагрузка' image=inherit cmd='ms-settings:startupapps')
		}
		menu(title='Персонализация' image=inherit)
		{
			item(title='Персонализация' image=inherit cmd='ms-settings:personalization')
			item(title='Экран блокировки' image=inherit cmd='ms-settings:lockscreen')
			item(title='Фон' image=inherit cmd='ms-settings:personalization-background')
			item(title='Цвета' image=inherit cmd='ms-settings:colors')
			item(title='Темы' image=inherit cmd='ms-settings:themes')
			item(title='Пуск' image=inherit cmd='ms-settings:personalization-start')
			item(title='Панель задач' image=inherit cmd='ms-settings:taskbar')
		}
		menu(title='Сеть' image=inherit)
		{
			item(title='Состояние' image=inherit cmd='ms-settings:network-status')
			item(title='Ethernet' image=inherit cmd='ms-settings:network-ethernet')
			item(title='Сетевые подключения' image=inherit cmd='shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}')
		}
	}
}
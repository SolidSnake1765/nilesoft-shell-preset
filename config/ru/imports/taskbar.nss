menu(type="taskbar" vis=key.shift() or key.lbutton() pos=0 title=app.name image=\uE249)
{
	item(title="Конфигурация" image=\uE10A cmd='"@app.cfg"')
	item(title="Менеджер" image=\uE0F3 admin cmd='"@app.exe"')
	item(title="Папка программы" image=\uE0E8 cmd='"@app.dir"')
	item(title="Версия\t"+@app.ver vis=label col=1)
	// Тема: скрипт переписывает строку import в shell.nss (wait=1 — ждём его), @app.reload — Nilesoft перечитает
	// конфиг при следующем открытии меню, без перезапуска Проводника
	menu(title='Тема' image=\uE116)
	{
		item(title='Акрил' checked=(preset_theme=='acrylic') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value acrylic -Folder "@app.dir" @app.reload')
		item(title='Modern' checked=(preset_theme=='modern') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value modern -Folder "@app.dir" @app.reload')
		item(title='Светлая' checked=(preset_theme=='light') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value light -Folder "@app.dir" @app.reload')
		item(title='Неон' checked=(preset_theme=='neon') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value neon -Folder "@app.dir" @app.reload')
		item(title='Dracula' checked=(preset_theme=='dracula') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value dracula -Folder "@app.dir" @app.reload')
		item(title='Nord' checked=(preset_theme=='nord') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value nord -Folder "@app.dir" @app.reload')
		item(title='Кодек' checked=(preset_theme=='codec') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value codec -Folder "@app.dir" @app.reload')
		item(title='Закат' checked=(preset_theme=='sunset') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value sunset -Folder "@app.dir" @app.reload')
		sep
		item(title='macOS' checked=(preset_theme=='macos') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value macos -Folder "@app.dir" @app.reload')
		item(title='Бирюзовое стекло' checked=(preset_theme=='glass') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value glass -Folder "@app.dir" @app.reload')
		item(title='Fluent (цвет акцента Windows)' checked=(preset_theme=='fluent') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value fluent -Folder "@app.dir" @app.reload')
	}
	item(title="Документация" image=\uE1C4 cmd='https://nilesoft.org/docs')
	item(title="Поддержать автора" image=\uE1A7 cmd='https://nilesoft.org/donate')
}
menu(where=@(this.count == 0) type='taskbar' image=icon.settings expanded=true)
{
	menu(title="Приложения" image=\uE254)
	{
		item(title='Paint' image=\uE116 cmd='mspaint')
		item(title='Edge' image cmd='@sys.prog32\Microsoft\Edge\Application\msedge.exe')
		item(title='Калькулятор' image=\ue1e7 cmd='calc.exe')
		item(title=str.res('regedit.exe,-16') image cmd='regedit.exe')
	}
	menu(title=title.windows image=\uE1FB)
	{
		item(title=title.cascade_windows cmd=command.cascade_windows)
		item(title=title.Show_windows_stacked cmd=command.Show_windows_stacked)
		item(title=title.Show_windows_side_by_side cmd=command.Show_windows_side_by_side)
		sep
		item(title=title.minimize_all_windows cmd=command.minimize_all_windows)
		item(title=title.restore_all_windows cmd=command.restore_all_windows)
	}
	item(title=title.desktop image=icon.desktop cmd=command.toggle_desktop)
	item(title=title.settings image=icon.settings(auto, image.color1) cmd='ms-settings:')
	item(title=title.task_manager sep=both image=icon.task_manager cmd='taskmgr.exe')
	item(title=title.taskbar_Settings sep=both image=inherit cmd='ms-settings:taskbar')
	item(vis=key.shift() title=title.exit_explorer cmd=command.restart_explorer)
}
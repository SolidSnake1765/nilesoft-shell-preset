menu(type="taskbar" vis=key.shift() or key.lbutton() pos=0 title=app.name image=\uE249)
{
	item(title="Configuration" image=\uE10A cmd='"@app.cfg"')
	item(title="Manager" image=\uE0F3 admin cmd='"@app.exe"')
	item(title="Program folder" image=\uE0E8 cmd='"@app.dir"')
	item(title="Version\t"+@app.ver vis=label col=1)
	// Theme: the script rewrites the import line in shell.nss (wait=1 - we wait for it), @app.reload - Nilesoft rereads
	// the config the next time a menu opens, without restarting Explorer
	menu(title='Theme' image=\uE116)
	{
		item(title='Acrylic' checked=(preset_theme=='acrylic') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value acrylic -Folder "@app.dir" @app.reload')
		item(title='Modern' checked=(preset_theme=='modern') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value modern -Folder "@app.dir" @app.reload')
		item(title='Light' checked=(preset_theme=='light') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value light -Folder "@app.dir" @app.reload')
		item(title='Neon' checked=(preset_theme=='neon') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value neon -Folder "@app.dir" @app.reload')
		item(title='Dracula' checked=(preset_theme=='dracula') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value dracula -Folder "@app.dir" @app.reload')
		item(title='Nord' checked=(preset_theme=='nord') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value nord -Folder "@app.dir" @app.reload')
		item(title='Codec' checked=(preset_theme=='codec') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value codec -Folder "@app.dir" @app.reload')
		item(title='Sunset' checked=(preset_theme=='sunset') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value sunset -Folder "@app.dir" @app.reload')
		sep
		item(title='macOS' checked=(preset_theme=='macos') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value macos -Folder "@app.dir" @app.reload')
		item(title='Turquoise glass' checked=(preset_theme=='glass') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value glass -Folder "@app.dir" @app.reload')
		item(title='Fluent (Windows accent color)' checked=(preset_theme=='fluent') window='hidden' wait=1
			cmd='powershell.exe' args='@tools_hidden -Action theme -Value fluent -Folder "@app.dir" @app.reload')
	}
	item(title="Documentation" image=\uE1C4 cmd='https://nilesoft.org/docs')
	item(title="Donate" image=\uE1A7 cmd='https://nilesoft.org/donate')
}
menu(where=@(this.count == 0) type='taskbar' image=icon.settings expanded=true)
{
	menu(title="Apps" image=\uE254)
	{
		item(title='Paint' image=\uE116 cmd='mspaint')
		item(title='Edge' image cmd='@sys.prog32\Microsoft\Edge\Application\msedge.exe')
		item(title='Calculator' image=\ue1e7 cmd='calc.exe')
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
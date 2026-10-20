menu(type='*' where=window.is_taskbar||sel.count mode=mode.multiple title=title.go_to sep=sep.both image=\uE14A)
{
	menu(title='Folders' image=\uE1F4)
	{
		item(title='Windows' image=inherit cmd=sys.dir)
		item(title='System32' image=inherit cmd=sys.bin)
		item(title='Program Files' image=inherit cmd=sys.prog)
		item(title='Program Files x86' image=inherit cmd=sys.prog32)
		item(title='ProgramData' image=inherit cmd=sys.programdata)
		item(title='Apps' image=inherit cmd='shell:appsfolder')
		item(title='Users' image=inherit cmd=sys.users)
		separator
		//item(title='@user.name@@@sys.name' vis=label)
		item(title='Desktop' image=inherit cmd=user.desktop)
		item(title='Downloads' image=inherit cmd=user.downloads)
		item(title='Pictures' image=inherit cmd=user.pictures)
		item(title='Documents' image=inherit cmd=user.documents)
		item(title='Start menu' image=inherit cmd=user.startmenu)
		item(title='Profile' image=inherit cmd=user.dir)
		item(title='AppData' image=inherit cmd=user.appdata)
		item(title='Temp' image=inherit cmd=user.temp)
	}
	item(title=title.control_panel image=\uE0F3 cmd='shell:::{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}')
	item(title='All Control Panel Items' image=\uE0F3 cmd='shell:::{ED7BA470-8E54-465E-825C-99712043E01C}')
	item(title=title.run image=\uE14B cmd='shell:::{2559a1f3-21d7-11d4-bdaf-00c04f60b9f0}')
	menu(where=sys.ver.major >= 10 title=title.settings sep=sep.before image=\uE0F3)
	{
		// https://docs.microsoft.com/en-us/windows/uwp/launch-resume/launch-settings-app
		item(title='System' image=inherit cmd='ms-settings:')
		item(title='About' image=inherit cmd='ms-settings:about')
		item(title='Your info' image=inherit cmd='ms-settings:yourinfo')
		item(title='System info' image=inherit cmd-line='/K systeminfo')
		item(title='Search' cmd='search-ms:' image=inherit)
		item(title='USB' image=inherit cmd='ms-settings:usb')
		item(title='Windows Update' image=inherit cmd='ms-settings:windowsupdate')
		item(title='Windows Security' image=inherit cmd='ms-settings:windowsdefender')
		menu(title='Apps' image=inherit)
		{
			item(title='Installed apps' image=inherit cmd='ms-settings:appsfeatures')
			item(title='Default apps' image=inherit cmd='ms-settings:defaultapps')
			item(title='Optional features' image=inherit cmd='ms-settings:optionalfeatures')
			item(title='Startup apps' image=inherit cmd='ms-settings:startupapps')
		}
		menu(title='Personalization' image=inherit)
		{
			item(title='Personalization' image=inherit cmd='ms-settings:personalization')
			item(title='Lock screen' image=inherit cmd='ms-settings:lockscreen')
			item(title='Background' image=inherit cmd='ms-settings:personalization-background')
			item(title='Colors' image=inherit cmd='ms-settings:colors')
			item(title='Themes' image=inherit cmd='ms-settings:themes')
			item(title='Start' image=inherit cmd='ms-settings:personalization-start')
			item(title='Taskbar' image=inherit cmd='ms-settings:taskbar')
		}
		menu(title='Network' image=inherit)
		{
			item(title='Status' image=inherit cmd='ms-settings:network-status')
			item(title='Ethernet' image=inherit cmd='ms-settings:network-ethernet')
			item(title='Network connections' image=inherit cmd='shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}')
		}
	}
}
menu(where=sel.count>0 type='file|dir|drive|namespace|back' mode="multiple" title='File manage' image=\uE253)
{
	menu(separator="after" title=title.copy_path image=icon.copy_path)
	{
		item(where=sel.count > 1 title='Copy paths (@sel.count items)' cmd=command.copy(sel(false, "\n")))
		item(mode="single" title=@sel.path tip=sel.path cmd=command.copy(sel.path))
		item(mode="single" type='file' separator="before" find='.lnk' title='Open file location')
		separator
		item(mode="single" where=@sel.parent.len>3 title=sel.parent cmd=@command.copy(sel.parent))
		separator
		item(mode="single" type='file|dir|back.dir' title=sel.file.name cmd=command.copy(sel.file.name))
		item(mode="single" type='file' where=sel.file.len != sel.file.title.len title=@sel.file.title cmd=command.copy(sel.file.title))
		item(mode="single" type='file' where=sel.file.ext.len>0 title=sel.file.ext cmd=command.copy(sel.file.ext))
	}

	item(mode="single" type="file" title="Change extension" image=\uE0B5 cmd=if(input("Change extension", "Enter the new extension"),
		io.rename(sel.path, path.join(sel.dir, sel.file.title + "." + input.result))))

	menu(separator="after" image=\uE290 title=title.select)
	{
		item(title="Select all" image=icon.select_all cmd=command.select_all)
		item(title="Invert selection" image=icon.invert_selection cmd=command.invert_selection)
		item(title="Select none" image=icon.select_none cmd=command.select_none)
		separator()
		// Smart select (tools-run.ps1 selects the files right in the Explorer window)
		menu(title='By type')
		{
			item(title='Video'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value video' window='hidden')
			item(title='Images'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value image' window='hidden')
			item(title='Music'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value audio' window='hidden')
			item(title='Documents'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value doc' window='hidden')
			item(title='Archives'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value archive' window='hidden')
			separator()
			item(title='Folders only'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value folders' window='hidden')
			item(title='Files only'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value files' window='hidden')
		}
		menu(title='By size')
		{
			item(title='Over 100 MB'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value big100' window='hidden')
			item(title='Over 1 GB'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value big1g' window='hidden')
			item(title='Empty files'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value empty' window='hidden')
		}
		menu(title='By date modified')
		{
			item(title='Today'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value today' window='hidden')
			item(title='This week'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value week' window='hidden')
			item(title='Older than 6 months'
				cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value old' window='hidden')
		}
		item(mode='single' type='file' title='Same extension'
			cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value sameext @sel(true," ")' window='hidden')
		item(title='By mask…'
			cmd='powershell.exe' args='@tools_hidden -Hwnd @wnd.handle -Folder "@sel.dir\." -Action select -Value mask' window='hidden')
	}

	item(type='file|dir|back.dir|drive' title='Take ownership' image=[\uE194,#f00] admin
		cmd args='/K takeown /f "@sel.path" @if(sel.type==1,null,"/r /d y") && icacls "@sel.path" /grant *S-1-5-32-544:F @if(sel.type==1,"/c /l","/t /c /l /q")')
	separator
	menu(title="Show/Hide" image=icon.show_hidden_files)
	{
		item(title="System files" image=inherit cmd='@command.togglehidden')
		item(title="File name extensions" image=icon.show_file_extensions cmd='@command.toggleext')
	}

	menu(type='file|dir|back.dir' mode="single" title='Attributes' image=icon.properties)
	{
		$atrr = io.attributes(sel.path)
		item(title='Hidden' checked=io.attribute.hidden(atrr)
			cmd args='/c ATTRIB @if(io.attribute.hidden(atrr),"-","+")H "@sel.path"' window=hidden)

		item(title='System' checked=io.attribute.system(atrr)
			cmd args='/c ATTRIB @if(io.attribute.system(atrr),"-","+")S "@sel.path"' window=hidden)

		item(title='Read-only' checked=io.attribute.readonly(atrr)
			cmd args='/c ATTRIB @if(io.attribute.readonly(atrr),"-","+")R "@sel.path"' window=hidden)

		item(title='Archive' checked=io.attribute.archive(atrr)
			cmd args='/c ATTRIB @if(io.attribute.archive(atrr),"-","+")A "@sel.path"' window=hidden)
		separator
		item(title="Created" keys=io.dt.created(sel.path, 'y/m/d') cmd=io.dt.created(sel.path,2000,1,1) vis=label)
		item(title="Modified" keys=io.dt.modified(sel.path, 'y/m/d') cmd=io.dt.modified(sel.path,2000,1,1) vis=label)
		item(title="Accessed" keys=io.dt.accessed(sel.path, 'y/m/d') cmd=io.dt.accessed(sel.path,2000,1,1) vis=label)
	}

	menu(mode="single" type='file' find='.dll|.ocx' separator="before" title='Register DLL' image=\uea86)
	{
		item(title='Register' admin cmd='regsvr32.exe' args='@sel.path.quote' invoke="multiple")
		item(title='Unregister' admin cmd='regsvr32.exe' args='/u @sel.path.quote' invoke="multiple")
	}

	menu(mode="single" type='back' expanded=true)
	{
		menu(separator="before" title='New folder' image=icon.new_folder)
		{
			item(title='With date and time' cmd=io.dir.create(sys.datetime("ymdHMSs")))
			item(title='With a random name (GUID)' cmd=io.dir.create(str.guid))
		}

		menu(title='New file' image=icon.new_file)
		{
			$dt = sys.datetime("ymdHMSs")
			item(title='TXT' cmd=io.file.create('@(dt).txt', 'Hello World!'))
			item(title='XML' cmd=io.file.create('@(dt).xml', '<root>Hello World!</root>'))
			item(title='JSON' cmd=io.file.create('@(dt).json', '[]'))
			item(title='HTML' cmd=io.file.create('@(dt).html', "<html>\n\t<head>\n\t</head>\n\t<body>Hello World!\n\t</body>\n</html>"))
		}
	}

	item(where=!wnd.is_desktop title=title.folder_options image=icon.folder_options cmd=command.folder_options)
}
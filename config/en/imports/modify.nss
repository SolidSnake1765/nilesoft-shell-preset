// modify items
// Remove items by identifiers
modify(mode=mode.multiple
	where=this.id(id.restore_previous_versions,id.cast_to_device)
	vis=vis.remove)

modify(type="recyclebin" where=window.is_desktop and this.id==id.empty_recycle_bin pos=1 sep)

// Russian Windows names these items in Russian, so both the Russian and the English names are listed
modify(find="unpin*|Открепить*" pos="bottom" menu="Pin/Unpin")
modify(find="pin*|Закрепить*" pos="top" menu="Pin/Unpin")

modify(where=this.id==id.copy_as_path menu="File manage")
modify(type="dir.back|drive.back" where=this.id==id.customize_this_folder pos=1 sep="top" menu="File manage")

modify(where=str.equals(this.name, ["open in terminal", "open linux shell here"]) || this.id==id.open_powershell_window_here
	pos="bottom" menu=title.terminal)

modify(mode=mode.multiple
	where=this.id(
		id.send_to,
		id.share,
		id.create_shortcut,
		id.set_as_desktop_background,
		id.rotate_left,
		id.rotate_right,
		id.map_network_drive,
		id.disconnect_network_drive,
		id.format,
		id.eject,
		id.give_access_to,
		id.include_in_library,
		id.print
	)
	pos=1 menu=title.more_options)

remove(mode=mode.multiple find='Проверка с использованием Microsoft Defender|Scan with Microsoft Defender')
// The system item is not needed: terminals have their own submenu
remove(mode=mode.multiple find='Открыть в Терминале|Open in Terminal')

// Rarely used program items go to the “Programs” submenu (declared in shell.nss)
// Git, VS Code, Compress Folder and Acrobat - everywhere
modify(mode=mode.multiple find='Open Git|с помощью Code|Open with Code|Compress Folder|Acrobat' menu="Programs")
// Players - only on folders (on files they stay in the main menu)
modify(mode=mode.multiple type='dir|back.dir' find='VLC|MPC-HC|AIMP' menu="Programs")

// The rules below are about specific programs. If a program is missing, its rule simply finds nothing

// Win 10 Tweaker items about ownership and internet access go to the “Access” submenu (declared in shell.nss)
modify(mode=mode.multiple find='Стать владельцем|доступ в интернет' menu="Access")

// NVIDIA items land in different menu groups - gather them together at the very bottom
modify(find='NVIDIA App' pos="bottom" sep="top")
modify(find='Панель управления NVIDIA|NVIDIA Control Panel' pos="bottom")
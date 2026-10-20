// modify items
// Remove items by identifiers
modify(mode=mode.multiple
	where=this.id(id.restore_previous_versions,id.cast_to_device)
	vis=vis.remove)

modify(type="recyclebin" where=window.is_desktop and this.id==id.empty_recycle_bin pos=1 sep)

// На русской Windows пункты называются «Закрепить…» и «Открепить…», английские оставлены на всякий случай
modify(find="unpin*|Открепить*" pos="bottom" menu="Закрепить/открепить")
modify(find="pin*|Закрепить*" pos="top" menu="Закрепить/открепить")

modify(where=this.id==id.copy_as_path menu="Управление файлами")
modify(type="dir.back|drive.back" where=this.id==id.customize_this_folder pos=1 sep="top" menu="Управление файлами")

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
// Системный пункт не нужен: терминалы и так есть в своём подменю
remove(mode=mode.multiple find='Открыть в Терминале|Open in Terminal')

// Редко нужные пункты программ — в подменю «Программы» (оно объявлено в shell.nss)
// Git, VS Code, Compress Folder и Acrobat — везде
modify(mode=mode.multiple find='Open Git|с помощью Code|Open with Code|Compress Folder|Acrobat' menu="Программы")
// Плееры — только на папках (на файлах остаются в основном меню)
modify(mode=mode.multiple type='dir|back.dir' find='VLC|MPC-HC|AIMP' menu="Программы")

// Правила ниже касаются конкретных программ. Если программы нет, правило просто ничего не находит

// Пункты Win 10 Tweaker про права и интернет — в подменю «Доступ» (оно объявлено в shell.nss)
modify(mode=mode.multiple find='Стать владельцем|доступ в интернет' menu="Доступ")

// Пункты NVIDIA вставляются в разные группы меню — собираем их вместе в самом низу
modify(find='NVIDIA App' pos="bottom" sep="top")
modify(find='Панель управления NVIDIA|NVIDIA Control Panel' pos="bottom")
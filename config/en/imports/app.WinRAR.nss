// Author: Rubic / RubicBG
// https://github.com/RubicBG/Nilesoft-Shell-Snippets/

// Hide default menu: NS can not recognize drag&drop paths, so use:
remove(find='Winrar')
//remove(clsid='{B41DB860-64E4-11D2-9906-E49FADC173CA}' where=!this.isuwp)

// Executables and Paths
$reg_winrar_exe		= reg.get('HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\WinRAR.exe') // path.combine(sys.prog, 'WinRar', 'WinRar.exe')
$reg_winrar_exe64	= reg.get('HKLM\Software\WinRAR', 'exe64')
// The 'exe64' value is missing on this PC, so use App Paths and fall back to the default install folder
$cmd_winrar 		= eval(if(path.exists(reg_winrar_exe), reg_winrar_exe, path.combine(sys.prog, 'WinRAR', 'WinRAR.exe')))
$cmd_winrar_path	= eval(path.parent(cmd_winrar))
// Software Support Extension
$cmd_winrar_sse = str.join(reg.values('HKLM\Software\WinRAR\Capabilities\FileAssociations'), '|')
// Theme and Icons
$path_winrar_theme	= path.combine(sys.appdata, 'WinRAR\Themes', reg('HKCU\Software\WinRAR\Interface\Themes', 'ActivePath'))
$img_winrar			= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'rar.ico')					, cmd_winrar)
$img_winrar_extract = If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'extract.png')	, cmd_winrar)
$img_winrar_add 	= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'add.png')		, cmd_winrar)
$img_winrar_delete	= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'delete.png')	, cmd_winrar)
$img_winrar_sfx 	= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'sfx.png')		, cmd_winrar)
$img_winrar_sfx_logo= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'sfxlogo.png')	, cmd_winrar)
$img_winrar_convert = If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'convert.png')	, cmd_winrar)
$img_winrar_test	= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'test.png')		, cmd_winrar)
$img_winrar_repair 	= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'repair.png')	, cmd_winrar)
$img_winrar_info 	= If(path.exists(path_winrar_theme), path.combine(path_winrar_theme, 'Toolbar', 'info.png')		, cmd_winrar)

menu(title='WinRar' mode='multiple' type='file|drive|dir|back.drive|back.dir|Desktop' image=img_winrar where=path.exists(cmd_winrar))
{
	item(title='Extract to...' keys='via the WinRAR window' sep='before'
		mode='multiple' type='file' find=cmd_winrar_sse image=image.res(img_winrar_extract)
		cmd=cmd_winrar args='x -iext -ver -imon1 @sel(true," -an=")' + ' "?\"')
	item(title='Extract to "@sel.path.title\"'
		mode='multiple' type='file' find=cmd_winrar_sse image=image.res(img_winrar_extract)
		cmd=cmd_winrar args='x -iext -ver -imon1 @sel(true," -an=")' + ' * "@sel.path.title \"')
	item(title='Extract to "@sel.path.title\" and delete the archive' vis=keys.shift()
		mode='single' type='file' find=cmd_winrar_sse image=image.res(img_winrar_delete) commands {
		cmd=cmd_winrar args='x -iext -ver -imon1 @sel(true)' + ' * "@sel.path.title \"' wait = 1,
		cmd=if(msg('Really delete the archive?', 'NileSoft Shell', msg.warning | msg.yesno)==msg.idyes, io.delete(sel)) wait = 1,
    	cmd=command.refresh wait = 1, })
	item(title='Extract each archive to its own folder'
		mode='multiple' type='file' where=sel.count>1 find=cmd_winrar_sse image=image(img_winrar_extract)
		cmd=cmd_winrar args='x -iext -ver -imon1 -ad1 @sel(true," -an=")' + ' * \')
	item(title='Extract here'
		mode='multiple' type='file' find=cmd_winrar_sse sep=sep.after image=image.res(img_winrar_extract)
		cmd=cmd_winrar args='x -iext -ver -imon1 @sel(true," -an=")' + ' * \')

	// known issue: can not add archive to itself
	item(title='Add to archive...' keys='via the WinRAR window' tip='Add to an archive via the WinRAR window'
		mode='multiple' type='file|dir' image=image.res(img_winrar_add) sep='before'
		cmd=cmd_winrar args='a -ep1 -scul -r0 -iext -imon1 . @sel(true)')
	menu(title='Add with a profile' mode='multiple' type='file|dir' image=image.res(img_winrar_add))
	{
		$reg_Prof0 = reg('HKCU\Software\WinRAR\Profiles\0', 'Name')
		$reg_Prof1 = reg('HKCU\Software\WinRAR\Profiles\1', 'Name')
		$reg_Prof2 = reg('HKCU\Software\WinRAR\Profiles\2', 'Name')
		$reg_Prof3 = reg('HKCU\Software\WinRAR\Profiles\3', 'Name')
		$reg_Prof4 = reg('HKCU\Software\WinRAR\Profiles\4', 'Name')
		$reg_Prof5 = reg('HKCU\Software\WinRAR\Profiles\5', 'Name')
		$reg_Prof6 = reg('HKCU\Software\WinRAR\Profiles\6', 'Name')
		$reg_Prof7 = reg('HKCU\Software\WinRAR\Profiles\7', 'Name')
		$reg_Prof8 = reg('HKCU\Software\WinRAR\Profiles\8', 'Name')
		$reg_Prof9 = reg('HKCU\Software\WinRAR\Profiles\9', 'Name')
		item(title=reg_Prof0 where=str.len(reg_Prof0)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof0" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof1 where=str.len(reg_Prof1)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof1" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof2 where=str.len(reg_Prof2)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof2" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof3 where=str.len(reg_Prof3)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof3" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof4 where=str.len(reg_Prof4)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof4" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof5 where=str.len(reg_Prof5)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof5" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof6 where=str.len(reg_Prof6)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof6" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof7 where=str.len(reg_Prof7)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof7" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof8 where=str.len(reg_Prof8)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof8" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
		item(title=reg_Prof9 where=str.len(reg_Prof9)>0
			cmd=cmd_winrar args='a -cp"@reg_Prof9" -ep1 -scul -r0 -iext -imon1 "@sel.title" @sel(true)')
	}

	item(title='Add to "@sel.title'+'.rar"' keys='SHIFT — to .zip' tip='Hold SHIFT to add to "@sel.title'+'.zip"'
		mode='multiple' type='file|dir' image=image.res(img_winrar_add)
		cmd=cmd_winrar args='a -ep1 -scul -r0 -iext -imon1 "@sel.title@if(key.shift(),".zip",".rar")" @sel(true)')
	item(title='Add to "@sel.parent.name'+'.rar"' keys='SHIFT — to .zip' tip='Hold SHIFT to add to "@sel.parent.name'+'.zip"'
		mode='multiple' type='file|dir' where=('@sel.file.title'!='@sel.parent.name') image=image.res(img_winrar_add)
		cmd=cmd_winrar args='a -ep1 -scul -r0 -iext -imon1 "@sel.parent.name@if(key.shift(),".zip",".rar")" @sel(true)')

	menu(title='More archiving options' type='file|dir|back.dir' image=image.res(img_winrar_add) sep=sep.after)
	{
		item(title='Turn the folder into "@sel.path.title'+'.rar"' keys='SHIFT — to .zip' tip='Hold SHIFT to add to "@sel.path'+'.zip"'
			mode='single' type='dir' where=len(path.files(sel.dir))>0 image=image.res(img_winrar_delete)
			cmd=cmd_winrar args='a -ep1 -scul -r0 -iext -imon1 -dr "@sel.path@if(key.shift(),".zip",".rar")" "@sel.path.title\*"')
		item(title='Move everything to "@sel.title'+'.rar"' keys='SHIFT — to .zip' tip='Hold SHIFT to add to "@sel.title'+'zip"'
			mode='single' type='back.dir' image=image.res(img_winrar_delete)
			cmd=cmd_winrar args='a -ep1 -scul -r0 -iext -imon1 -dr ".\@sel.title@if(key.shift(),".zip",".rar")" *')

		item(title='Create an SFX archive "@sel.title'+'.sfx.exe"'
			mode='multiple' type='file|dir' sep='before' image=image.res(img_winrar_sfx)
			cmd=cmd_winrar args='a -ep1 -scul -r0 -iext -imon1 -sfx "@sel.parent\@sel.title'+'.sfx.exe" @sel(true)')
	}

	item(title='Convert archives...'
		mode='multiple' type='file' find=cmd_winrar_sse image=image.res(img_winrar_convert)
		cmd=cmd_winrar args='cv -iext -imon1 @sel(true," -an=")')
	item(title='Test archives...'
		mode='multiple' type='file' find=cmd_winrar_sse image=image.res(img_winrar_test)
		cmd=cmd_winrar args='t -iext -idv -imon1 @sel(true," -an=")')
	item(title='Repair archive...'
		mode='single' type='file' find=cmd_winrar_sse sep=sep.after image=image.res(img_winrar_repair)
		cmd=cmd_winrar args='r -iext @sel.path(true)')

	// known issue: can not recognize sfx from exe
	item(title='Open in WinRAR...'
		mode='single' type='file' find=cmd_winrar_sse image=image.res(img_winrar)
		cmd=cmd_winrar args='-iext @sel.path(true)')
	item(title='Browse in WinRAR...'
		mode='single' type='drive|dir|back.drive|back.dir|Desktop' sep=sep.after image=image.res(img_winrar)
		cmd=cmd_winrar args='-iext @sel.path(true)')

	menu(title='WinRAR help' mode='multiple' where=key.shift() sep=sep.top image=image.res(img_winrar_info))
	{
		item(title='Documentation...'
			mode='multiple' image=image.res(img_winrar_info)
			cmd='@cmd_winrar_path\WinRAR.chm')
		item(title='Online support...'
			mode='multiple' image=image.res(img_winrar_info)
			cmd='https://www.win-rar.com/support.html')
		item(title='Install the Popcol theme'
			image=icon.res(path.combine(sys.bin, 'shell32.dll'), 122) commands {
			cmd-ps=`$DownloadURL = 'https://www.rarlab.com/themes/POPCOL_96x96.theme.rar'; $TempRarPath = '@sys.temp\POPCOL_96x96.theme.rar'; Invoke-WebRequest -Uri $DownloadURL -OutFile $TempRarPath; Start-Process -FilePath '@cmd_winrar' -ArgumentList $TempRarPath;` window='hidden' wait='true',
			cmd=reg.set('HKCU\Software\WinRAR\Interface\Themes', 'ActivePath', 'POPCOL_96x96', reg.sz) wait='true',
			cmd-ps=`$TempRarPath = '@sys.temp\POPCOL_96x96.theme.rar'; Remove-Item -Path $TempRarPath -Force;` window='hidden' wait='true', })
		item(title='Update WinRAR...'
			image=icon.res(path.combine(sys.bin, 'shell32.dll'), 122)
			cmd-ps='winget install --id=RARLab.WinRAR -e')
	}
}

// menu(title=menu_archiver mode='multiple' type='*' where=window.name=="static" image=[[\uE019],[\uE01A]] position=top) { item(title='Test' type='*' where=window.name=="static" tip=sel) }


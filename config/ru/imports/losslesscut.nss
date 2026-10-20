// LosslessCut — быстрая обрезка видео и звука без перекодирования
// Путь к программе ($lc_exe) задаётся в imports/paths.nss. Если LosslessCut не найден, пункта нет.
// Расширения, для которых показывается пункт
$lc_ext = '.mp4|.mkv|.mov|.avi|.webm|.m4v|.ts|.mts|.m2ts|.flv|.wmv|.mpg|.mpeg|.3gp|.mp3|.m4a|.aac|.flac|.wav|.ogg|.opus'

// Несколько выбранных файлов откроются в LosslessCut одним списком
item(title='Открыть в LosslessCut' mode='multiple' type='file' find=lc_ext
	where=path.exists(lc_exe) image=lc_exe cmd=lc_exe args=sel(true))

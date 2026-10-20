// LosslessCut — fast video and audio trimming without re-encoding
// The path to the program ($lc_exe) is set in imports/paths.nss. If LosslessCut is not found, the item is hidden.
// Extensions the item is shown for
$lc_ext = '.mp4|.mkv|.mov|.avi|.webm|.m4v|.ts|.mts|.m2ts|.flv|.wmv|.mpg|.mpeg|.3gp|.mp3|.m4a|.aac|.flac|.wav|.ogg|.opus'

// Several selected files open in LosslessCut as one list
item(title='Open in LosslessCut' mode='multiple' type='file' find=lc_ext
	where=path.exists(lc_exe) image=lc_exe cmd=lc_exe args=sel(true))

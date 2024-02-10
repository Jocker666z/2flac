# 2flac

Various lossless to FLAC while keeping the tags.

Lossless audio codec supported: ALAC, APE, DSF, FLAC, WAV, WAVPACK

--------------------------------------------------------------------------------------------------
## Install & update
`curl https://raw.githubusercontent.com/Jocker666z/2flac/master/2flac.sh > /home/$USER/.local/bin/2flac && chmod +rx /home/$USER/.local/bin/2flac`

## Dependencies
`ffmpeg flac mutagen-inspect`

## Use
Processes all compatible files in the current directory and his three subdirectories.
```
Options:
  --16bits_only           Compress only 16bits source.
  --alac_only             Compress only ALAC source.
  --ape_only              Compress only Monkey's Audio source.
  --dsd_only              Compress only DSD source.
  --flac_only             Compress only FLAC source.
  --wav_only              Compress only WAV source.
  --wavpack_only          Compress only WAVPACK source.
  -v, --verbose           More verbose, for debug.

Supported source files:
  * ALAC in .caf .m4a
  * DSD in .dsf
  * FLAC in .flac .ogg
  * Monkey's Audio in .ape
  * PCM in .caf .wav
  * WAVPACK in .wv
```

Notes: 
* FLAC compression is `--lax -8pl32`.
* DSF is converted at 24bit/192kHz, for a coherent final file size.
* Converted tags are according with musicbrainz (as far as possible) (https://picard-docs.musicbrainz.org/en/appendices/tag_mapping.html).

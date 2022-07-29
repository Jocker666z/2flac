# 2flac

Various lossless to FLAC while keeping the tags.

Lossless audio source supported: ALAC, APE, FLAC, WAV, WAVPACK

--------------------------------------------------------------------------------------------------
## Install & update
`curl https://raw.githubusercontent.com/Jocker666z/2flac/master/2flac.sh > /home/$USER/.local/bin/2flac && chmod +rx /home/$USER/.local/bin/2flac`

## Dependencies
`ffmpeg flac monkeys-audio wavpack`

## Use
Processes all compatible files in the current directory and his three subdirectories.
```
Options:
  --16bits_only           Compress only 16bits source.
  --re_flac               Recompress WAVPACK source.
  --alac_only             Compress only ALAC source.
  --ape_only              Compress only Monkey's Audio source.
  --wav_only              Compress only WAV source.
  --wavpack_only          Compress only WAVPACK source.
  -v, --verbose           More verbose, for debug.
```
* ALAC as .m4a
* Monkey's Audio as .ape
* WAVPACK as .wv
* WAV as .wav

Default compression is `-8 -e -p`.

#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2086,SC2207
# 2flac
# Various lossless to FLAC while keeping the tags.
# \(^o^)/ 
#
# Author : Romain Barbarot
# https://github.com/Jocker666z/2flac/
# Licence : unlicense

# Search & populate array with source files
search_source_files() {
local codec_test

mapfile -t lst_audio_src < <(find "$PWD" -maxdepth 3 -type f -regextype posix-egrep \
								-iregex '.*\.('$input_ext')$' 2>/dev/null | sort)

# Only clean
for i in "${!lst_audio_src[@]}"; do

	if [[ "${bits16_only}" = "1" ]] \
	&& [[ "${cd_resample}" != "1" ]]; then
		codec_test=$(ffprobe -v error -select_streams a:0 \
			-show_entries stream=sample_fmt -of csv=s=x:p=0 "${lst_audio_src[i]}"  )
		if [[ "$codec_test" != "s16" ]] \
		&& [[ "$codec_test" != "s16p" ]]; then
			unset "lst_audio_src[i]"
		fi
	fi

	if [[ "${alac_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "caf" \
	   && "${lst_audio_src[i]##*.}" != "m4a" ]]; then
			unset "lst_audio_src[i]"
	fi
	# Keep only ALAC codec in m4a
	if [[ "${lst_audio_src[i]##*.}" = "caf" ]] \
	|| [[ "${lst_audio_src[i]##*.}" = "m4a" ]]; then
		codec_test=$(ffprobe -v error -select_streams a:0 \
			-show_entries stream=codec_name -of csv=s=x:p=0 \
			"${lst_audio_src[i]}" )
		if [[ "$codec_test" != "alac" ]] \
		&& [[ "$codec_test" != "pcm_"* ]]; then
			unset "lst_audio_src[i]"
		fi
	fi

	if [[ "${ape_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "ape" ]]; then
			unset "lst_audio_src[i]"
	fi

	if [[ "${dsd_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "dsf" ]]; then
			unset "lst_audio_src[i]"
	fi

	if [[ "${flac_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "flac" \
	   && "${lst_audio_src[i]##*.}" != "ogg" ]]; then
			unset "lst_audio_src[i]"
	fi

	# Keep only FLAC codec in ogg
	if [[ "${lst_audio_src[i]##*.}" = "ogg" ]]; then
		codec_test=$(ffprobe -v error -select_streams a:0 \
			-show_entries stream=codec_name -of csv=s=x:p=0 \
			"${lst_audio_src[i]}" )
		if [[ "$codec_test" != "flac" ]]; then
			unset "lst_audio_src[i]"
		fi
	fi

	if [[ "${tta_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "tta" ]]; then
			unset "lst_audio_src[i]"
	fi

	if [[ "${wav_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "wav" ]]; then
			unset "lst_audio_src[i]"
	fi

	if [[ "${wavpack_only}" = "1" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "wv" ]]; then
			unset "lst_audio_src[i]"
	fi

done
}
# Verify source integrity
test_source() {
local test_counter

test_counter="0"

# Test
for file in "${lst_audio_src[@]}"; do
	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		test_counter=$((test_counter+1))
		if [[ "${#lst_audio_src[@]}" = "1" ]]; then
			echo -ne "${test_counter}/${#lst_audio_src[@]} source file is being tested"\\r
		else
			echo -ne "${test_counter}/${#lst_audio_src[@]} source files are being tested"\\r
		fi
	fi

	(

	if [[ "${file##*.}" = "flac" ]]; then
		flac $flac_test_arg "$file" 2>"${cache_dir}/${file##*/}.decode_error.log"
	else
		ffmpeg -v error -i "$file" \
			-vn -sn -dn -max_muxing_queue_size 9999 \
			-f null - 2>"${cache_dir}/${file##*/}.decode_error.log"

		# Ignore ffmpeg non-blocking errors
		if [ -s "${cache_dir}/${file##*/}.decode_error.log" ]; then
			# [mjpeg @ ...] unable to decode APP fields...
			if < "${cache_dir}/${file##*/}.decode_error.log" \
				grep  -E "mjpeg.*APP fields" &>/dev/null; then
				rm "${cache_dir}/${file##*/}.decode_error.log"
			# [... @ ...] Unknown attached ... image/webp.
			elif < "${cache_dir}/${file##*/}.decode_error.log" \
				grep -E "*image/webp" &>/dev/null; then
				rm "${cache_dir}/${file##*/}.decode_error.log"
			fi
		fi
	fi

	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi
done
wait

# Test if error generated
for file in "${lst_audio_src[@]}"; do
	# FLAC - Special fix loop
	if [[ "${file##*.}" = "flac" ]]; then
		# Error log test
		if [ -s "${cache_dir}/${file##*/}.decode_error.log" ]; then
			# Try to fix file
			flac $flac_fix_arg "$file"
			# Re-test, if no valid 2 times exclude
			flac $flac_test_arg "$file" 2>"${cache_dir}/${file##*/}.decode_error.log"
		fi
	fi

	# Errors validation
	if [ -s "${cache_dir}/${file##*/}.decode_error.log" ]; then
		mv "${cache_dir}/${file##*/}.decode_error.log" "${file}.decode_error.log"
		lst_audio_src_rejected+=( "$file" )
	else
		rm "${cache_dir}/${file##*/}.decode_error.log"  2>/dev/null
		lst_audio_src_pass+=( "$file" )
	fi
done

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if (( "${#lst_audio_src_rejected[@]}" )); then
		if [[ "${#lst_audio_src[@]}" = "1" ]]; then
			echo "${test_counter} source file tested ~ ${#lst_audio_src_rejected[@]} in error (log generated)"
		else
			echo "${test_counter} source files tested ~ ${#lst_audio_src_rejected[@]} in error (log generated)"
		fi
	else
		if [[ "${#lst_audio_src[@]}" = "1" ]]; then
			echo "${test_counter} source file tested"
		else
			echo "${test_counter} source files tested"
		fi
	fi
fi

# All source files size record
total_source_files_size=$(calc_files_size "${lst_audio_src_pass[@]}")
# Individual source file size record
for file in "${lst_audio_src_pass[@]}"; do
	file_source_files_size+=( "$(get_files_size_bytes "${file}")" )
done
}
# Decode source
decode_source() {
local decode_counter
local test_bit
local ffmpeg_arg_bit

decode_counter="0"

for file in "${lst_audio_src_pass[@]}"; do
	(

	if [[ "${file##*.}" = "ape" ]] \
	|| [[ "${file##*.}" = "caf" ]] \
	|| [[ "${file##*.}" = "m4a" ]] \
	|| [[ "${file##*.}" = "tta" ]] \
	|| [[ "${file##*.}" = "wv" ]]; then

		# Bit test, for prevent bad convert in auto
		test_bit=$(ffprobe -v panic -show_entries \
						stream=sample_fmt -print_format csv=p=0 "$file")
		# 8 & 16bit
		if [[ "$test_bit" == "s8"* ]] \
		|| [[ "$test_bit" == "u8"* ]] \
		|| [[ "$test_bit" == "s16"* ]]; then
			ffmpeg_arg_bit="-c:a pcm_s16le"
		# 24bit
		elif [[ "$test_bit" == "s24"* ]]; then
			ffmpeg_arg_bit="-c:a pcm_s24le"
		# 32 & 64bit
		elif [[ "$test_bit" == "s32"* ]] \
		  || [[ "$test_bit" = "f32" ]] \
		  || [[ "$test_bit" = "fltp" ]] \
		  || [[ "$test_bit" == "f64"* ]] \
		  || [[ "$test_bit" == "s64"* ]] \
		  || [[ "$test_bit" = "dblp" ]]; then
			ffmpeg_arg_bit="-c:a pcm_s32le"
		fi

		ffmpeg $ffmpeg_log_lvl -y -i "$file" $ffmpeg_arg_bit "${cache_dir}/${file##*/}.wav"
	elif [[ "${file##*.}" = "dsf" ]]; then
		ffmpeg $ffmpeg_log_lvl -y -i "$file" \
			-c:a pcm_s32le -ar 384000 \
			"${cache_dir}/${file##*/}.wav"
	fi

	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi

	# FLAC target array
	if [[ "${file##*.}" = "flac" ]] \
	|| [[ "${file##*.}" = "ogg" ]] \
	|| [[ "${file##*.}" = "wav" ]]; then
		lst_audio_wav_decoded+=( "$file" )
	else
		decode_counter=$((decode_counter+1))
		lst_audio_wav_decoded+=( "${cache_dir}/${file##*/}.wav" )
	fi

	# Array of source at remove
	if [[ "${file##*.}" != "flac" ]]; then
		lst_audio_src_to_remove+=( "$file" )
	fi

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
			echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
		else
			echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
		fi
	fi

done
wait

# Progress end
if [[ "$verbose" != "1" ]];then
	tput hpa 0; tput el
	if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
		echo "${decode_counter} source file decoded"
	else
		echo "${decode_counter} source files decoded"
	fi
fi
}
# Convert tag to VORBIS
apev2_sub () {
source_tag[i]="${source_tag[i]//Album Artist=/ALBUMARTIST=}"
source_tag[i]="${source_tag[i]//Arranger=/ARRANGER=}"
source_tag[i]="${source_tag[i]//Barcode=/BARCODE=}"
source_tag[i]="${source_tag[i]//CatalogNumber=/CATALOGNUMBER=}"
source_tag[i]="${source_tag[i]//Comment=/COMMENT=}"
source_tag[i]="${source_tag[i]//Compilation=/COMPILATION=}"
source_tag[i]="${source_tag[i]//Composer=/COMPOSER=}"
source_tag[i]="${source_tag[i]//Conductor=/CONDUCTOR=}"
source_tag[i]="${source_tag[i]//Copyright=/COPYRIGHT=}"
source_tag[i]="${source_tag[i]//Year=/DATE=}"
source_tag[i]="${source_tag[i]//Director=/DIRECTOR=}"
source_tag[i]="${source_tag[i]//Disc=/DISCNUMBER=}"
source_tag[i]="${source_tag[i]//DiscSubtitle=/DISCSUBTITLE=}"
source_tag[i]="${source_tag[i]//DJMixer=/DJMIXER=}"
source_tag[i]="${source_tag[i]//Engineer=/ENGINEER=}"
source_tag[i]="${source_tag[i]//Genre=/GENRE=}"
source_tag[i]="${source_tag[i]//Grouping=/GROUPING=}"
source_tag[i]="${source_tag[i]//Label=/LABEL=}"
source_tag[i]="${source_tag[i]//Language=/LANGUAGE=}"
source_tag[i]="${source_tag[i]//Lyricist=/LYRICIST=}"
source_tag[i]="${source_tag[i]//Lyrics=/LYRICS=}"
source_tag[i]="${source_tag[i]//Media=/MEDIA=}"
source_tag[i]="${source_tag[i]//Mixer=/MIXER=}"
source_tag[i]="${source_tag[i]//Mood=/MOOD=}"
source_tag[i]="${source_tag[i]//Performer=/PERFORMER=}"
source_tag[i]="${source_tag[i]//MUSICBRAINZ_ALBUMSTATUS=/RELEASESTATUS=}"
source_tag[i]="${source_tag[i]//MUSICBRAINZ_ALBUMTYPE=/RELEASETYPE=}"
source_tag[i]="${source_tag[i]//MixArtist=/REMIXER=}"
source_tag[i]="${source_tag[i]//Script=/SCRIPT=}"
source_tag[i]="${source_tag[i]//Subtitle=/SUBTITLE=}"
source_tag[i]="${source_tag[i]//Title=/TITLE=}"
source_tag[i]="${source_tag[i]//Track=/TRACKNUMBER=}"
source_tag[i]="${source_tag[i]//Weblink=/WEBSITE=}"
source_tag[i]="${source_tag[i]//Writer=/WRITER=}"
}
id3v2_sub () {
source_tag[i]="${source_tag[i]//TALB=/ALBUM=}"
source_tag[i]="${source_tag[i]//TBPM=/BPM=}"
source_tag[i]="${source_tag[i]//TCMP=/COMPILATION=}"
source_tag[i]="${source_tag[i]//TCON=/GENRE=}"
source_tag[i]="${source_tag[i]//TCOP=/COPYRIGHT=}"
source_tag[i]="${source_tag[i]//TDOR=/ORIGINALDATE=}"
source_tag[i]="${source_tag[i]//TDRC=/DATE=}"
source_tag[i]="${source_tag[i]//TEXT=/LYRICIST=}"
source_tag[i]="${source_tag[i]//TIT1=/GROUPING=}"
source_tag[i]="${source_tag[i]//TIT2=/TITLE=}"
source_tag[i]="${source_tag[i]//TIT3=/SUBTITLE=}"
source_tag[i]="${source_tag[i]//TLAN=/LANGUAGE=}"
source_tag[i]="${source_tag[i]//TMED=/MEDIA=}"
source_tag[i]="${source_tag[i]//TMOO=/MOOD=}"
source_tag[i]="${source_tag[i]//TOFN=/ORIGINALFILENAME=}"
source_tag[i]="${source_tag[i]//TPOS=/DISCNUMBER=}"
source_tag[i]="${source_tag[i]//TPE1=/ARTIST=}"
source_tag[i]="${source_tag[i]//TPE2=/ALBUMARTIST=}"
source_tag[i]="${source_tag[i]//TPE3=/CONDUCTOR=}"
source_tag[i]="${source_tag[i]//TPE4=/REMIXER=}"
source_tag[i]="${source_tag[i]//TPUB=/LABEL=}"
source_tag[i]="${source_tag[i]//TRCK=/TRACKNUMBER=}"
source_tag[i]="${source_tag[i]//TSO2=/ALBUMARTISTSORT=}"
source_tag[i]="${source_tag[i]//TSOC=/COMPOSERSORT=}"
source_tag[i]="${source_tag[i]//TSOP=/ARTISTSORT=}"
source_tag[i]="${source_tag[i]//TSOT=/TITLESORT=}"
source_tag[i]="${source_tag[i]//TSRC=/ISRC=}"
source_tag[i]="${source_tag[i]//TSST=/DISCSUBTITLE=}"
source_tag[i]="${source_tag[i]//TXXX=Acoustid Id=/ACOUSTID_ID=}"
source_tag[i]="${source_tag[i]//TXXX=Acoustid Fingerprint=/ACOUSTID_FINGERPRINT=}"
source_tag[i]="${source_tag[i]//TXXX=ARTISTS=/ARTISTS=}"
source_tag[i]="${source_tag[i]//TXXX=ASIN=/ASIN=}"
source_tag[i]="${source_tag[i]//TXXX=BARCODE=/BARCODE=}"
source_tag[i]="${source_tag[i]//TXXX=CATALOGNUMBER=/CATALOGNUMBER=}"
source_tag[i]="${source_tag[i]//TXXX=COMPOSERSORT=/COMPOSERSORT=}"
source_tag[i]="${source_tag[i]//TXXX=DIRECTOR=/DIRECTOR=}"
source_tag[i]="${source_tag[i]//TXXX=LICENSE=/LICENSE=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Album Artist Id=/MUSICBRAINZ_ALBUMARTISTID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Album Id=/MUSICBRAINZ_ALBUMID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Album Status=/RELEASESTATUS=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Album Type=/RELEASETYPE=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Artist Id=/MUSICBRAINZ_ARTISTID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Album Release Country=/RELEASECOUNTRY=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Release Group Id=/MUSICBRAINZ_RELEASEGROUPID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Release Track Id=/MUSICBRAINZ_RELEASETRACKID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz TRM Id=/MUSICBRAINZ_TRMID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicBrainz Work Id=/MUSICBRAINZ_WORKID=}"
source_tag[i]="${source_tag[i]//TXXX=MusicIP PUID=/MUSICIP_PUID=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_ALBUM_GAIN=/REPLAYGAIN_ALBUM_GAIN=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_ALBUM_PEAK=/REPLAYGAIN_ALBUM_PEAK=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_ALBUM_RANGE=/REPLAYGAIN_ALBUM_RANGE=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_REFERENCE_LOUDNESS=/REPLAYGAIN_REFERENCE_LOUDNESS=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_TRACK_GAIN=/REPLAYGAIN_TRACK_GAIN=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_TRACK_PEAK=/REPLAYGAIN_TRACK_PEAK=}"
source_tag[i]="${source_tag[i]//TXXX=REPLAYGAIN_TRACK_RANGE=/REPLAYGAIN_TRACK_RANGE=}"
source_tag[i]="${source_tag[i]//TXXX=SCRIPT=/SCRIPT=}"
source_tag[i]="${source_tag[i]//TXXX=SHOWMOVEMENT=/SHOWMOVEMENT=}"
source_tag[i]="${source_tag[i]//TXXX=WORK=/WORK=}"
source_tag[i]="${source_tag[i]//TXXX=Writer=/WRITER=}"
source_tag[i]="${source_tag[i]//UFID=/MUSICBRAINZ_TRACKID=}"
source_tag[i]="${source_tag[i]//WCOP=/LICENSE=}"
source_tag[i]="${source_tag[i]//WOAR=/WEBSITE=}"
}
itune_sub () {
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:Acoustid Id=/ACOUSTID_ID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:Acoustid Fingerprint=/ACOUSTID_FINGERPRINT=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:ARTISTS=/ARTISTS=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:ASIN=/ASIN=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:BARCODE=/BARCODE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:CATALOGNUMBER=/CATALOGNUMBER=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:CONDUCTOR=/CONDUCTOR=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:DISCSUBTITLE=/DISCSUBTITLE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:DJMIXER=/DJMIXER=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:ENGINEER=/ENGINEER=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:ISRC=/ISRC=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:LABEL=/LABEL=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:LANGUAGE=/LANGUAGE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:LICENSE=/LICENSE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:LYRICIST=/LYRICIST=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MEDIA=/MEDIA=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MIXER=/MIXER=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MOOD=/MOOD=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Album Artist Id=/MUSICBRAINZ_ALBUMARTISTID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Album Id=/MUSICBRAINZ_ALBUMID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Album Release Country=/RELEASECOUNTRY=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Album Status=/RELEASESTATUS=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Album Type=/RELEASETYPE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Artist Id=/MUSICBRAINZ_ARTISTID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Release Group Id=/MUSICBRAINZ_RELEASEGROUPID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Release Track Id=/MUSICBRAINZ_RELEASETRACKID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Track Id=/MUSICBRAINZ_TRACKID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz TRM Id=/MUSICBRAINZ_TRMID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicBrainz Work Id=/MUSICBRAINZ_WORKID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:MusicIP PUID=/MUSICIP_PUID=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REMIXER=/REMIXER=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_ALBUM_GAIN=/REPLAYGAIN_ALBUM_GAIN=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_ALBUM_PEAK=/REPLAYGAIN_ALBUM_PEAK=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_ALBUM_RANGE=/REPLAYGAIN_ALBUM_RANGE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_REFERENCE_LOUDNESS=/REPLAYGAIN_REFERENCE_LOUDNESS=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_TRACK_GAIN=/REPLAYGAIN_TRACK_GAIN=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_TRACK_PEAK=/REPLAYGAIN_TRACK_PEAK=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:REPLAYGAIN_TRACK_RANGE=/REPLAYGAIN_TRACK_RANGE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:SCRIPT=/SCRIPT=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:SUBTITLE=/SUBTITLE=}"
source_tag[i]="${source_tag[i]//©alb=/ALBUM=}"
source_tag[i]="${source_tag[i]//©ART=/ARTIST=}"
source_tag[i]="${source_tag[i]//©cmt=/COMMENT=}"
source_tag[i]="${source_tag[i]//©day=/DATE=}"
source_tag[i]="${source_tag[i]//©dir=/DIRECTOR=}"
source_tag[i]="${source_tag[i]//©gen=/GENRE=}"
source_tag[i]="${source_tag[i]//©grp=/GROUPING=}"
source_tag[i]="${source_tag[i]//©mvn=/MOVEMENTNAME=}"
source_tag[i]="${source_tag[i]//©nam=/TITLE=}"
source_tag[i]="${source_tag[i]//©wrk=/WORK=}"
source_tag[i]="${source_tag[i]//aART=/ALBUMARTIST=}"
source_tag[i]="${source_tag[i]//cpil=/COMPILATION=}"
source_tag[i]="${source_tag[i]//cprt=/COPYRIGHT=}"
source_tag[i]="${source_tag[i]//disk=/DISCNUMBER=}"
source_tag[i]="${source_tag[i]//mvc=/MOVEMENTTOTAL=}"
source_tag[i]="${source_tag[i]//mvi=/MOVEMENT=}"
source_tag[i]="${source_tag[i]//shwm=/SHOWMOVEMENT=}"
source_tag[i]="${source_tag[i]//soaa=/ALBUMARTISTSORT=}"
source_tag[i]="${source_tag[i]//soar=/ARTISTSORT=}"
source_tag[i]="${source_tag[i]//soco=/COMPOSERSORT=}"
source_tag[i]="${source_tag[i]//sonm=/TITLESORT=}"
source_tag[i]="${source_tag[i]//trkn=/TRACKNUMBER=}"
}
other_sub () {
# MusicBrainz internal name
source_tag[i]="${source_tag[i]//albumartistsort=/ALBUMARTISTSORT=}"
source_tag[i]="${source_tag[i]//artistsort=/ARTISTSORT=}"
source_tag[i]="${source_tag[i]//musicbrainz_albumid=/MUSICBRAINZ_ALBUMID=}"
source_tag[i]="${source_tag[i]//musicbrainz_artistid=/MUSICBRAINZ_ARTISTID=}"
source_tag[i]="${source_tag[i]//musicbrainz_recordingid=/MUSICBRAINZ_TRACKID=}"
source_tag[i]="${source_tag[i]//musicbrainz_releasegroupid=/MUSICBRAINZ_RELEASEGROUPID=}"
source_tag[i]="${source_tag[i]//originalyear=/ORIGINALYEAR=}"
source_tag[i]="${source_tag[i]//replaygain_album_gain=/REPLAYGAIN_ALBUM_GAIN=}"
source_tag[i]="${source_tag[i]//replaygain_album_peak=/REPLAYGAIN_ALBUM_PEAK=}"
source_tag[i]="${source_tag[i]//replaygain_track_gain=/REPLAYGAIN_TRACK_GAIN=}"
source_tag[i]="${source_tag[i]//replaygain_track_peak=/REPLAYGAIN_TRACK_PEAK=}"
# Waste fix
shopt -s nocasematch
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:originaldate=/ORIGINALDATE=}"
source_tag[i]="${source_tag[i]//----:com.apple.iTunes:originalyear=/ORIGINALYEAR=}"
source_tag[i]="${source_tag[i]//date=/DATE=}"
source_tag[i]="${source_tag[i]//originaldate=/ORIGINALDATE=}"
source_tag[i]="${source_tag[i]//TXXX=originalyear=/ORIGINALYEAR=}"
shopt -u nocasematch
}
tags_2_flac() {
local exclude_from_tag_loop
local cover_test
local cover_image_type
local cover_ext
local tag_label
local grab_tag_counter
local tag_trick
local tag_trick_str

grab_tag_counter="0"

for file in "${lst_audio_flac_compressed[@]}"; do

	# Reset
	unset exclude_from_tag_loop
	unset source_tag
	unset source_tag_temp
	unset source_tag_temp1
	unset source_tag_temp2
	unset tag_name
	unset tag_label
	unset tag_trick
	unset tag_trick_str

	# Target file
	if [[ -s "${file%.*}.ape" ]]; then
		file="${file%.*}.ape"
	elif [[ -s "${file%.*}.dsf" ]]; then
		file="${file%.*}.dsf"
	elif [[ -s "${file%.*}.m4a" ]]; then
		file="${file%.*}.m4a"
	elif [[ -s "${file%.*}.tta" ]]; then
		file="${file%.*}.tta"
	elif [[ -s "${file%.*}.wv" ]]; then
		file="${file%.*}.wv"
	else
		exclude_from_tag_loop="1"
	fi

	# Get tag if src != wav or flac
	if [[ "$exclude_from_tag_loop" != "1" ]]; then

		# If ReplayGain or not
		if [[ "$replay_gain" != "1" ]]; then
			Vorbis_whitelist=("${Vorbis_whitelist[@]}" "${Vorbis_whitelist_replaygain[@]}")
		fi

		# Source file tags array
		mapfile -t source_tag < <( mutagen-inspect "$file" )
		# itune need clean
		if [[ -s "${file%.*}.m4a" ]]; then
			for i in "${!source_tag[@]}"; do
				source_tag[i]="${source_tag[i]//MP4FreeForm(b\'/}"
				source_tag[i]="${source_tag[i]//\', <AtomDataType.UTF8: 1>)/}"
				if [[ "${source_tag[i]}" = "disk="* ]] \
				|| [[ "${source_tag[i]}" = *"trkn="* ]]; then
					source_tag[i]="${source_tag[i]//disk=(/disk=}"
					source_tag[i]="${source_tag[i]//trkn=(/trkn=}"
					source_tag[i]="${source_tag[i]//, //}"
					source_tag[i]="${source_tag[i]//)/}"
				fi
			done
		fi

		# Try to extract cover, if no cover in directory
		if [[ ! -e "${file%/*}"/cover.jpg ]] \
		&& [[ ! -e "${file%/*}"/cover.png ]]; then
			cover_test=$(ffprobe -v error -select_streams v:0 \
						-show_entries stream=codec_name -of csv=s=x:p=0 \
						"$file" 2>/dev/null)
			if [[ -n "$cover_test" ]]; then
				if [[ "$cover_test" = "png" ]]; then
					cover_ext="png"
				elif [[ "$cover_test" = *"jpeg"* ]]; then
					cover_ext="jpg"
				fi
				ffmpeg $ffmpeg_log_lvl -n -i "$file" \
					"${file%/*}"/cover."$cover_ext" 2>/dev/null
			fi
		fi

		# Remove empty tag label=
		mapfile -t source_tag < <( printf '%s\n' "${source_tag[@]}" | grep "=" )

		# Exclude no tag source; & FLAC, WAV
		if (( "${#source_tag[@]}" )); then

			# Substitution
			for i in "${!source_tag[@]}"; do
				# APEv2
				apev2_sub
				# ID3v2
				id3v2_sub
				# iTune
				itune_sub
				# MusicBrainz internal name & waste
				other_sub
			done

			# Array tag name & label
			mapfile -t tag_name < <( printf '%s\n' "${source_tag[@]}" | awk -F "=" '{print $1}' )
			mapfile -t tag_label < <( printf '%s\n' "${source_tag[@]}" | cut -f2- -d'=' )

			# Whitelist parsing
			for i in "${!tag_name[@]}"; do
				for tag in "${Vorbis_whitelist[@]}"; do
					# Vorbis std
					if [[ "${tag_name[i],,}" = "${tag,,}" ]] \
					&& [[ -n "${tag_label[i]// }" ]]; then

					# Picard std
					if [[ "${tag}" = "TRACKNUMBER" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						source_tag+=( "TOTALTRACKS=${tag_label[i]#*/}" )
					fi
					if [[ "${tag}" = "DISCNUMBER" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						source_tag+=( "TOTALDISCS=${tag_label[i]#*/}" )
					fi
					if [[ "${tag}" = "TRACKNUMBER" ]] \
					|| [[ "${tag}" = "DISCNUMBER" ]]; then
						tag_label[i]="${tag_label[i]%/*}"
					fi
					if [[ "${tag}" = "LABEL" ]] \
					&& [[ "${tag_label[i]}" = *"\xc"* ]]; then
						tag_label[i]=$(printf "%b" "${tag_label[i]}")
					fi


					if [[ "${tag}" = "ARTISTS" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "ARTISTS=${type}" )
						done
					elif [[ "${tag}" = "MUSICBRAINZ_ARTISTID" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "MUSICBRAINZ_ARTISTID=${type}" )
						done
					elif [[ "${tag}" = "ISRC" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "ISRC=${type}" )
						done
					elif [[ "${tag}" = "LABEL" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "LABEL=${type}" )
						done
					elif [[ "${tag}" = "MUSICBRAINZ_TRACKID" ]] \
					&& [[ "${tag_label[i]}" = *"'"* ]]; then
						tag_trick_str=$(echo "${tag_label[i]}" \
									| cut  -d "'" -f2)
						source_tag+=( "MUSICBRAINZ_TRACKID=${tag_trick_str}" )
					elif [[ "${tag}" = "MUSICBRAINZ_ALBUMARTISTID" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "MUSICBRAINZ_ALBUMARTISTID=${type}" )
						done
					elif [[ "${tag}" = "RELEASETYPE" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "RELEASETYPE=${type}" )
						done
					elif [[ "${tag}" = "PERFORMER" ]] \
					&& [[ "${tag_label[i]}" = *"/"* ]]; then
						mapfile -t tag_trick < <( echo "${tag_label[i]//\//|}" \
										| tr "|" "\n" \
										| awk '$1=$1' )
						for type in "${tag_trick[@]}"; do
							source_tag+=( "PERFORMER=${type}" )
						done
					else
							# Array of tag
							source_tag[i]="${tag}=${tag_label[i]}"
					fi

						continue 2
					# reject
					else
						unset "source_tag[i]"
					fi
				done
			done

			# Remove duplicate tags
			mapfile -t source_tag < <( printf '%s\n' "${source_tag[@]}" | uniq -u )

			# Tag FLAC
			for i in "${!source_tag[@]}"; do
				metaflac "${file%.*}.flac" --set-tag="${source_tag[i]}"
			done

			# Tag counter
			grab_tag_counter=$((grab_tag_counter+1))

		fi

		# Progress
		if ! [[ "$verbose" = "1" ]]; then
			if [[ "${#lst_audio_flac_compressed[@]}" = "1" ]]; then
				echo -ne "${grab_tag_counter}/${#lst_audio_flac_compressed[@]} flac file is being tagged"\\r
			else
				echo -ne "${grab_tag_counter}/${#lst_audio_flac_compressed[@]} flac files are being tagged"\\r
			fi
		fi

	fi


	# FLAC->FLAC try to extract cover
	if [[ ! -s "${file%.*}.caf" ]] \
	&& [[ ! -s "${file%.*}.wav" ]] \
	&& [[ "$exclude_from_tag_loop" = "1" ]]; then

		cover_test=$(metaflac --list "${file%.*}.flac" \
				| grep -A 8 METADATA 2>/dev/null \
				| grep -A 7 -B 1 PICTURE 2>/dev/null)

		if [[ -n "$cover_test" ]]; then
			# Image type
			cover_image_type=$(echo "$cover_test" \
								| grep "MIME type" \
								| awk -F " " '{print $NF}' \
								| awk -F "/" '{print $NF}' \
								| head -1)
			if [[ "$cover_image_type" = "png" ]]; then
				cover_ext="png"
			elif [[ "$cover_image_type" = "jpeg" ]]; then
				cover_ext="jpg"
			elif [[ "$cover_image_type" = "webp" ]]; then
				cover_ext="webp"
			fi
			# Extract
			metaflac "${file%.*}.flac" \
				--export-picture-to="${file%.*}.$cover_ext"
		fi

	fi

done

# FLAC->FLAC Delete embedded & ReplayGain if active
for file in "${lst_audio_flac_compressed[@]}"; do

	# Reset
	unset exclude_from_tag_loop

	# Target file
	if [[ ! -s "${file%.*}.ape" ]] \
	&& [[ ! -s "${file%.*}.caf" ]] \
	&& [[ ! -s "${file%.*}.dsf" ]] \
	&& [[ ! -s "${file%.*}.m4a" ]] \
	&& [[ ! -s "${file%.*}.tta" ]] \
	&& [[ ! -s "${file%.*}.wv" ]] \
	&& [[ ! -s "${file%.*}.wav" ]]; then
		exclude_from_tag_loop="1"
	fi

	(
	if [[ "$replay_gain" = "1" || "$rm_replay_gain" = "1" ]] \
	&& [[ "$exclude_from_tag_loop" = "1" ]]; then
		metaflac "${file%.*}.flac" \
			--remove --block-type=PICTURE,PADDING \
			--dont-use-padding \
			--remove-replay-gain
	elif [[ "$exclude_from_tag_loop" = "1" ]]; then
		metaflac "${file%.*}.flac" \
			--remove --block-type=PICTURE,PADDING \
			--dont-use-padding
	fi
	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi
done
wait

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if [[ "${#lst_audio_flac_compressed[@]}" = "1" ]]; then
		echo "${grab_tag_counter} flac file tagged"
	else
		echo "${grab_tag_counter} flac files tagged"
	fi
fi
}
# FLAC - Compress
compress_flac() {
local compress_counter

compress_counter="0"

for i in "${!lst_audio_src_pass[@]}"; do
	# Compress FLAC
	(
	if [[ "$verbose" = "1" ]]; then
		flac $flac_compress_arg "${lst_audio_wav_decoded[i]}" \
			-o "${lst_audio_src_pass[i]%.*}".flac
	else
		flac $flac_compress_arg "${lst_audio_wav_decoded[i]}" \
			-o "${lst_audio_src_pass[i]%.*}".flac &>/dev/null
	fi
	) &
	if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
		wait -n
	fi

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		compress_counter=$((compress_counter+1))
		if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
			echo -ne "${compress_counter}/${#lst_audio_wav_decoded[@]} flac file is being compressed"\\r
		else
			echo -ne "${compress_counter}/${#lst_audio_wav_decoded[@]} flac files are being compressed"\\r
		fi
	fi
done
wait

# Progress end
if ! [[ "$verbose" = "1" ]]; then
	tput hpa 0; tput el
	if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
		echo "${compress_counter} flac file compressed"
	else
		echo "${compress_counter} flac files compressed"
	fi
fi

# Clean + target array
for i in "${!lst_audio_wav_decoded[@]}"; do
	# Array of FLAC target
	lst_audio_flac_compressed+=( "${lst_audio_src_pass[i]%.*}.flac" )

	# Remove temp wav files
	if [[ "${lst_audio_src[i]##*.}" != "wav" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "ogg" ]] \
	&& [[ "${lst_audio_src[i]##*.}" != "flac" ]]; then
		rm -f "${lst_audio_wav_decoded[i]%.*}.wav" 2>/dev/null
	fi
done
}
# CD Resample 16/44.1
cd_format() {
local sox_counter
local source_hz
local source_bit
local source_channel

sox_counter="0"

if [[ "$cd_resample" = "1" ]]; then

	for i in "${!lst_audio_wav_decoded[@]}"; do

		# Test source
		source_hz=$(sox --i -r "${lst_audio_wav_decoded[i]}")
		source_bit=$(sox --i -b "${lst_audio_wav_decoded[i]}")
		source_channel=$(sox --i -c "${lst_audio_wav_decoded[i]}")

		# Counter
		if [[ "$source_hz" != "44100" ]] \
		|| [[ "$source_bit" != "16" ]] \
		|| [[ "$source_channel" != "2" ]]; then
			sox_counter=$((sox_counter+1))
		fi

		# Resample
		(
		if [[ "$verbose" = "1" ]]; then
			if [[ "$source_hz" != "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" = "2" ]]; then
				sox -S "${lst_audio_wav_decoded[i]}" \
					-C 0 -b 16 "${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither
			elif [[ "$source_hz" != "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" != "2" ]]; then
				sox -S "${lst_audio_wav_decoded[i]}" \
					-C 0 -c 2 -b 16 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither
			elif [[ "$source_hz" != "44100" \
				 && "$source_bit" = "16" \
				 && "$source_channel" = "2" ]]; then
				sox -S "${lst_audio_wav_decoded[i]}" \
					-C 0 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither
			elif [[ "$source_hz" != "44100" \
				 && "$source_bit" = "16" \
				 && "$source_channel" != "2" ]]; then
				sox -S "${lst_audio_wav_decoded[i]}" \
					-C 0 -c 2 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither
			elif [[ "$source_hz" = "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" = "2" ]]; then
				sox -S "${lst_audio_wav_decoded[i]}" \
					-C 0 -b 16 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac"
			elif [[ "$source_hz" = "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" != "2" ]]; then
				sox -S "${lst_audio_wav_decoded[i]}" \
					-C 0 -c 2 -b 16 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac"
			fi
		else
			if [[ "$source_hz" != "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" = "2" ]]; then
				sox "${lst_audio_wav_decoded[i]}" \
					-C 0 -b 16 "${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither &>/dev/null
			elif [[ "$source_hz" != "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" != "2" ]]; then
				sox "${lst_audio_wav_decoded[i]}" \
					-C 0 -c 2 -b 16 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither &>/dev/null
			elif [[ "$source_hz" != "44100" \
				 && "$source_bit" = "16" \
				 && "$source_channel" = "2" ]]; then
				sox "${lst_audio_wav_decoded[i]}" \
					-C 0 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither &>/dev/null
			elif [[ "$source_hz" != "44100" \
				 && "$source_bit" = "16" \
				 && "$source_channel" != "2" ]]; then
				sox "${lst_audio_wav_decoded[i]}" \
					-c 2 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					rate -v -L -s 44100 dither &>/dev/null
			elif [[ "$source_hz" = "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" = "2" ]]; then
				sox "${lst_audio_wav_decoded[i]}" \
					-C 0 -b 16 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					&>/dev/null
			elif [[ "$source_hz" = "44100" \
				 && "$source_bit" != "16" \
				 && "$source_channel" != "2" ]]; then
				sox "${lst_audio_wav_decoded[i]}" \
					-C 0 -c 2 -b 16 \
					"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
					&>/dev/null
			fi
		fi

		# Test target & replace source
		if flac $flac_test_arg "${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" 2>/dev/null; then
			rm "${lst_audio_wav_decoded[i]}"
			mv "${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
				"${lst_audio_wav_decoded[i]}"
		else
			sox_counter=$((sox_counter-1))
		fi

		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi

		# Progress
		if ! [[ "$verbose" = "1" ]]; then
			if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
				echo -ne "${sox_counter}/${#lst_audio_wav_decoded[@]} flac file is being resampled"\\r
			else
				echo -ne "${sox_counter}/${#lst_audio_wav_decoded[@]} flac files are being resampled"\\r
			fi
		fi

	done
	wait

	# Progress end
	if ! [[ "$verbose" = "1" ]]; then
		tput hpa 0; tput el
		if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
			echo "${sox_counter} flac file resampled"
		else
			echo "${sox_counter} flac files resampled"
		fi
	fi

fi
}
# Resample 48kHz
khz48_format() {
local sox_counter
local source_hz

sox_counter="0"

if [[ "$khz48_format" = "1" ]]; then

	for i in "${!lst_audio_wav_decoded[@]}"; do

		# Test source
		source_hz=$(sox --i -r "${lst_audio_wav_decoded[i]}")

		# Counter
		if [[ "$source_hz" -gt "48000" ]]; then
			sox_counter=$((sox_counter+1))
		fi

		# Resample
		(
		if [[ "$verbose" = "1" ]] \
		&& [[ "$source_hz" -gt "48000" ]]; then
			sox -S "${lst_audio_wav_decoded[i]}" \
				-C 0 \
				"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
				rate -v -L -s 48000 dither
		elif [[ "$source_hz" -gt "48000" ]]; then
			sox "${lst_audio_wav_decoded[i]}" \
				-C 0 \
				"${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
				rate -v -L -s 48000 dither &>/dev/null
		fi

		# Test target & replace source
		if flac $flac_test_arg "${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" 2>/dev/null; then
			rm "${lst_audio_wav_decoded[i]}"
			mv "${cache_dir}/${lst_audio_wav_decoded[i]##*/}.sox.flac" \
				"${lst_audio_wav_decoded[i]}"
		else
			sox_counter=$((sox_counter-1))
		fi

		) &
		if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
			wait -n
		fi

		# Progress
		if ! [[ "$verbose" = "1" ]]; then
			if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
				echo -ne "${sox_counter}/${#lst_audio_wav_decoded[@]} flac file is being resampled"\\r
			else
				echo -ne "${sox_counter}/${#lst_audio_wav_decoded[@]} flac files are being resampled"\\r
			fi
		fi

	done
	wait

	# Progress end
	if ! [[ "$verbose" = "1" ]]; then
		tput hpa 0; tput el
		if [[ "${#lst_audio_wav_decoded[@]}" = "1" ]]; then
			echo "${sox_counter} flac file resampled"
		else
			echo "${sox_counter} flac files resampled"
		fi
	fi

fi
}
# Replay gain
replay_gain() {
local metaflac_counter

metaflac_counter="0"

if [[ "$replay_gain" = "1" ]]; then

	# Select rsgain by default if installed
	if command -v rsgain &>/dev/null; then

		for file in "${lst_audio_flac_compressed[@]}"; do
			(
			rsgain custom -q -c a -s i "$file"
			) &
			if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
				wait -n
			fi

			# Progress
			metaflac_counter=$((metaflac_counter+1))
			if ! [[ "$verbose" = "1" ]]; then
				echo -ne "${metaflac_counter}/${#lst_audio_flac_compressed[@]} replay gain applied"\\r
			fi
		done
		wait

	else

		for file in "${lst_audio_flac_compressed[@]}"; do
			(
				metaflac --add-replay-gain "$file"
			) &
			if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
				wait -n
			fi

			# Progress
			metaflac_counter=$((metaflac_counter+1))
			if ! [[ "$verbose" = "1" ]]; then
				echo -ne "${metaflac_counter}/${#lst_audio_flac_compressed[@]} replay gain applied"\\r
			fi
		done
		wait

	fi

	# Progress end
	if ! [[ "$verbose" = "1" ]]; then
		tput hpa 0; tput el
		echo "${#lst_audio_flac_compressed[@]} replay gain applied"
	fi

fi
}
# Total size calculation in MB - Input must be in bytes
calc_files_size() {
local files
local size
local size_in_mb

files=("$@")

if (( "${#files[@]}" )); then
	# Get size in bytes
	if ! [[ "${files[-1]}" =~ ^[0-9]+$ ]]; then
		size=$(wc -c "${files[@]}" | tail -1 | awk '{print $1;}')
	else
		size="${files[-1]}"
	fi
	# Mb convert
	size_in_mb=$(bc <<< "scale=1; $size / 1024 / 1024" | sed 's!\.0*$!!')
else
	size_in_mb="0"
fi

# If string start by "." add lead 0
if [[ "${size_in_mb:0:1}" == "." ]]; then
	size_in_mb="0$size_in_mb"
fi

# If GB not display float
size_in_mb_integer="${size_in_mb%%.*}"
if [[ "${#size_in_mb_integer}" -ge "4" ]]; then
	size_in_mb="$size_in_mb_integer"
fi

echo "$size_in_mb"
}
# Get file size in bytes
get_files_size_bytes() {
local files
local size
files=("$@")

if (( "${#files[@]}" )); then
	# Get size in bytes
	size=$(wc -c "${files[@]}" | tail -1 | awk '{print $1;}')
fi

echo "$size"
}
# Percentage calculation
calc_percent() {
local total
local value
local perc

value="$1"
total="$2"

if [[ "$value" = "$total" ]]; then
	echo "00.00"
else
	# Percentage calculation
	perc=$(bc <<< "scale=4; ($total - $value)/$value * 100")
	# If string start by "." or "-." add lead 0
	if [[ "${perc:0:1}" == "." ]] || [[ "${perc:0:2}" == "-." ]]; then
		if [[ "${perc:0:2}" == "-." ]]; then
			perc="${perc/-./-0.}"
		else
			perc="${perc/./+0.}"
		fi
	fi
	# If string start by integer add lead +
	if [[ "${perc:0:1}" =~ ^[0-9]+$ ]]; then
			perc="+${perc}"
	fi
	# Keep only 5 first digit
	perc="${perc:0:5}"

	echo "$perc"
fi
}
# Display tricks
display_list_truncate() {
local list
local term_widh_truncate

list=("$@")

term_widh_truncate=$(stty size | awk '{print $2}' | awk '{ print $1 - 8 }')

for line in "${list[@]}"; do
	if [[ "${#line}" -gt "$term_widh_truncate" ]]; then
		echo -e " $line" | cut -c 1-"$term_widh_truncate" | awk '{print $0"..."}'
	else
		echo -e " $line"
	fi
done
}
# Summary of processing
summary_of_processing() {
local time_formated
local file_target_files_size
local file_diff_percentage
local file_path_truncate
local file_replaygain
local total_target_files_size
local total_diff_size
local total_diff_percentage

if (( "${#lst_audio_src[@]}" )); then
	time_formated="$((SECONDS/3600))h$((SECONDS%3600/60))m$((SECONDS%60))s"

	# All files pass size stats & label
	if (( "${#lst_audio_src_pass[@]}" )); then
		for i in "${!lst_audio_src_pass[@]}"; do
			# Make statistics of indidual processed files
			file_target_files_size=$(get_files_size_bytes "${lst_audio_flac_compressed[i]}")
			file_diff_percentage=$(calc_percent "${file_source_files_size[i]}" "$file_target_files_size")
			filesPassSizeReduction+=( "$file_diff_percentage" )
			file_path_truncate=$(echo "${lst_audio_flac_compressed[i]}" | rev | cut -d'/' -f-2 | rev)
			if [[ "$replay_gain" = "1" ]]; then
				file_replaygain=$(mutagen-inspect "${lst_audio_flac_compressed[i]}" \
									| grep "REPLAYGAIN_TRACK_GAIN")
				file_replaygain="${file_replaygain//REPLAYGAIN_TRACK_GAIN=/}"
				file_replaygain="${file_replaygain//[[:blank:]]/} ~ "
				if [[ "${file_replaygain:0:1}" =~ ^[0-9]+$ ]]; then
					file_replaygain="+${file_replaygain}"
				fi
			fi
			filesPassLabel+=( "${filesPassSizeReduction[i]}% ~ ${file_replaygain}.${file_path_truncate}" )
		done
	fi
	# All files rejected size label
	if (( "${#lst_audio_src_rejected[@]}" )); then
		for i in "${!lst_audio_src_rejected[@]}"; do
			file_path_truncate=$(echo "${lst_audio_src_rejected[i]}" | rev | cut -d'/' -f-2 | rev)
			filesRejectedLabel+=( ".${file_path_truncate}" )
		done
	fi
	# Total files size stats
	total_target_files_size=$(calc_files_size "${lst_audio_flac_compressed[@]}")
	total_diff_size=$(bc <<< "scale=0; ($total_target_files_size - $total_source_files_size)" \
						| sed -r 's/^(-?)\./\10./')
	total_diff_percentage=$(calc_percent "$total_source_files_size" "$total_target_files_size")

	# Print list of files stats
	if (( "${#lst_audio_src_pass[@]}" )); then
		echo
		echo "File(s) created:"
		display_list_truncate "${filesPassLabel[@]}"
	fi
	# Print list of files reject
	if (( "${#lst_audio_src_rejected[@]}" )); then
		echo
		echo "File(s) in error:"
		display_list_truncate "${filesRejectedLabel[@]}"
	fi
	# Print all files stats
	echo
	echo "${#lst_audio_flac_compressed[@]}/${#lst_audio_src[@]} file(s) compressed to FLAC for a total of ${total_target_files_size}MB."
	echo "${total_diff_percentage}% difference with the source files, ${total_diff_size}MB on ${total_source_files_size}MB."
	echo "Processing end: $(date +%D\ at\ %Hh%Mm) - Duration: ${time_formated}."
	echo
fi
}
# Remove source files
remove_source_files() {
if [[ "${#lst_audio_src_to_remove[@]}" -gt 0 ]] ; then
	read -r -p "Remove source files? [y/N]:" qarm
	case $qarm in
		"Y"|"y")
			# Remove source files
			for file in "${lst_audio_src_to_remove[@]}"; do
				rm -f "$file" 2>/dev/null
			done
		;;
		*)
			source_not_removed="1"
		;;
	esac
else
	read -r -p "Press an input for exit" qarm
	case $qarm in
		*)
			return
		;;
	esac
fi
}
# Remove target files
remove_target_files() {
if [[ "$source_not_removed" = "1" ]] ; then
	read -r -p "Remove target files? [y/N]:" qarm
	case $qarm in
		"Y"|"y")
			# Remove source files
			for file in "${lst_audio_src_to_remove[@]}"; do
				rm -f "${file%.*}.flac" 2>/dev/null
			done
		;;
	esac
fi
}
# Test dependencies
command_label() {
if [[ "$command" = "ffprobe" ]]; then
	command="$command (ffmpeg package)"
fi
if [[ "$command" = "metaflac" ]]; then
	command="$command (flac package)"
fi
if [[ "$command" = "mutagen-inspect" ]]; then
	command="$command (python3-mutagen package)"
fi
}
command_display() {
local label
label="$1"
if (( "${#command_fail[@]}" )); then
	echo
	echo "Please install the $label dependencies:"
	display_list_truncate "${command_fail[@]}"
	echo
	exit
fi
}
command_test() {
n=0;
for command in "${core_dependencies[@]}"; do
	if hash "$command" &>/dev/null; then
		(( c++ )) || true
	else
		command_label
		command_fail+=("[!] $command")
		(( n++ )) || true
	fi
done
command_display "2flac"
}
# Cache
cache() {
# Check cache directory
if [ ! -d "$cache_dir" ]; then
	mkdir "$cache_dir"
fi

# Consider if file exist in cache directory after 1 days, delete it
find "$cache_dir/" -type f -mtime +1 -exec /bin/rm -f {} \;
}
# Usage print
usage() {
cat <<- EOF
2flac - GNU GPL-2.0 Copyright - <https://github.com/Jocker666z/2flac>
Various lossless to FLAC while keeping the tags.

Processes all compatible files in the current directory
and his three subdirectories.

Usage:
2flac [options]

Options:
  --48khz                 Force resample to 48kHz.
  --cd                    Force resample to stereo 16bit/44.1kHz.
  --fast                  Use fast compress instead default.
  --replay-gain           Apply ReplayGain to each track.
  --replay-gain-no        Not keep the ReplayGain.
  --16bits_only           Compress only 16bits source.
  --alac_only             Compress only ALAC source.
  --ape_only              Compress only Monkey's Audio source.
  --dsd_only              Compress only DSD source.
  --flac_only             Compress only FLAC source.
  --tta_only              Compress only TTA source.
  --wav_only              Compress only WAV source.
  --wavpack_only          Compress only WAVPACK source.
  -v, --verbose           More verbose, for debug.

Supported source files:
  * ALAC in .caf .m4a
  * DSD in .dsf
  * FLAC in .flac .ogg
  * Monkey's Audio in .ape
  * PCM in .caf .wav
  * The True Audio in .tta
  * WAVPACK in .wv
EOF
}

# Need Dependencies
core_dependencies=(ffmpeg ffprobe flac metaflac mutagen-inspect sox)
# Paths
export PATH=$PATH:/home/$USER/.local/bin
cache_dir="/tmp/2flac"
# Nb process parrallel (nb of processor)
nproc=$(grep -cE 'processor' /proc/cpuinfo)
# Input extention available
input_ext="ape|caf|dsf|flac|m4a|ogg|tta|wv|wav"
# FFMPEG
ffmpeg_log_lvl="-hide_banner -loglevel panic -nostats"
# FLAC
flac_version=$(flac -v)
flac_test_arg="--no-md5-sum --no-warnings-as-errors -s -t"
flac_fix_arg="--totally-silent -f --verify --decode-through-errors"
flac_compress_arg="-f --lax -8pl32"
# Tag whitelist according with:
# https://picard-docs.musicbrainz.org/en/appendices/tag_mapping.html
# Ommit: ENCODEDBY, ENCODERSETTINGS
Vorbis_whitelist=(
	'ACOUSTID_ID'
	'ACOUSTID_FINGERPRINT'
	'ALBUM'
	'ALBUMARTIST'
	'ALBUMARTISTSORT'
	'ALBUMSORT'
	'ARRANGER'
	'ARTIST'
	'ARTISTSORT'
	'ARTISTS'
	'ASIN'
	'BARCODE'
	'BPM'
	'CATALOGNUMBER'
	'COMMENT'
	'COMPILATION'
	'COMPOSER'
	'COMPOSERSORT'
	'CONDUCTOR'
	'COPYRIGHT'
	'DIRECTOR'
	'DISCNUMBER'
	'DISCSUBTITLE'
	'ENGINEER'
	'GENRE'
	'GROUPING'
	'KEY'
	'ISRC'
	'LANGUAGE'
	'LICENSE'
	'LYRICIST'
	'LYRICS'
	'MEDIA'
	'DJMIXER'
	'MIXER'
	'MOOD'
	'MOVEMENTNAME'
	'MOVEMENTTOTAL'
	'MOVEMENT'
	'MUSICBRAINZ_ARTISTID'
	'MUSICBRAINZ_DISCID'
	'MUSICBRAINZ_ORIGINALARTISTID'
	'MUSICBRAINZ_ORIGINALALBUMID'
	'MUSICBRAINZ_TRACKID'
	'MUSICBRAINZ_ALBUMARTISTID'
	'MUSICBRAINZ_RELEASEGROUPID'
	'MUSICBRAINZ_ALBUMID'
	'MUSICBRAINZ_RELEASETRACKID'
	'MUSICBRAINZ_TRMID'
	'MUSICBRAINZ_WORKID'
	'MUSICIP_PUID'
	'ORIGINALFILENAME'
	'ORIGINALDATE'
	'ORIGINALYEAR'
	'PERFORMER'
	'PRODUCER'
	'RATING'
	'LABEL'
	'RELEASECOUNTRY'
	'DATE'
	'RELEASESTATUS'
	'RELEASETYPE'
	'REMIXER'
	'SCRIPT'
	'SHOWMOVEMENT'
	'SUBTITLE'
	'TOTALDISCS'
	'DISCTOTAL'
	'TRACKTOTAL'
	'TOTALTRACKS'
	'TRACKNUMBER'
	'TITLE'
	'TITLESORT'
	'WEBSITE'
	'WORK'
	'WRITER'
)
Vorbis_whitelist_replaygain=(
	'REPLAYGAIN_ALBUM_GAIN'
	'REPLAYGAIN_ALBUM_PEAK'
	'REPLAYGAIN_ALBUM_RANGE'
	'REPLAYGAIN_REFERENCE_LOUDNESS'
	'REPLAYGAIN_TRACK_GAIN'
	'REPLAYGAIN_TRACK_PEAK'
	'REPLAYGAIN_TRACK_RANGE'
)

# Command arguments
while [[ $# -gt 0 ]]; do
	key="$1"
	case "$key" in
	-h|--help)
		usage
		exit
	;;
	"--48khz")
		khz48_format="1"
		if [[ "$khz48_format" = "1" ]] \
		&& [[ "$cd_resample" = "1" ]]; then
			echo "/!\ 48kHz or 44.1kHz, that's the question."
			exit
		fi
	;;
	"--cd")
		cd_resample="1"
		if [[ "$khz48_format" = "1" ]] \
		&& [[ "$cd_resample" = "1" ]]; then
			echo "/!\ 48kHz or 44.1kHz, that's the question."
			exit
		fi
	;;
	"--fast")
		flac_compress_arg="-f --compression-level-0"
	;;
	"--replay-gain")
		replay_gain="1"
	;;
	"--replay-gain-no")
		rm_replay_gain="1"
	;;
	"--16bits_only")
		bits16_only="1"
	;;
	"--alac_only")
		alac_only="1"
	;;
	"--ape_only")
		ape_only="1"
	;;
	"--dsd_only")
		dsd_only="1"
	;;
	"--flac_only")
		flac_only="1"
	;;
	"--tta_only")
		tta_only="1"
	;;
	"--wav_only")
		wav_only="1"
	;;
	"--wavpack_only")
		wavpack_only="1"
	;;
	-v|--verbose)
		verbose="1"
	;;
	*)
		usage
		exit
	;;
esac
shift
done

# Cache test
cache

# Test dependencies
command_test

# Find source files
search_source_files

# Start main
if (( "${#lst_audio_src[@]}" )); then
	echo
	echo "2flac start processing with $flac_version \(^o^)/"
	echo "Working directory: $(echo ${PWD} | rev | cut -d'/' -f-1 | rev)"
	echo
	echo "${#lst_audio_src[@]} source files found"

	# Test
	test_source

	# Decode
	decode_source

	# Resample
	cd_format
	khz48_format

	# Compress
	compress_flac

	# Tag
	tags_2_flac

	# Replay gain
	replay_gain

	# End
	summary_of_processing
	if (( "${#lst_audio_flac_compressed[@]}" )); then
		remove_source_files
		remove_target_files
	fi
fi
exit

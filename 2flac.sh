#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2086
# 2flac
# Various lossless to FLAC while keeping the tags.
# \(^o^)/ 
#
# It does this:
#    Array namme
#  1 lst_audio_src              get source list
#  2 lst_audio_src_pass         source pass
#  2 lst_audio_src_rejected     source no pass
#  3 lst_audio_wav_decoded      source -> WAV
#  4 lst_audio_flac_compressed  WAV -> FLAC
#  5 source_tag                 TAG -> FLAC
#
# Author : Romain Barbarot
# https://github.com/Jocker666z/2flac/
# Licence : unlicense

# Search & populate array with source files
search_source_files() {
local codec_test

if [[ "$re_flac" = "1" ]];then
	mapfile -t lst_audio_src < <(find "$PWD" -maxdepth 3 -type f -regextype posix-egrep \
									-iregex '.*\.('flac')$' 2>/dev/null | sort)
else
	mapfile -t lst_audio_src < <(find "$PWD" -maxdepth 3 -type f -regextype posix-egrep \
									-iregex '.*\.('$input_ext')$' 2>/dev/null | sort)

	# Keep only ALAC if arg --alac_only
	if [[ "${alac_only}" = "1" ]]; then
		for i in "${!lst_audio_src[@]}"; do
			if [[ "${lst_audio_src[i]##*.}" != "m4a" ]]; then
					unset "lst_audio_src[$i]"
			fi
		done
	fi
	# Keep only DSD if arg --dsd_only
	if [[ "${dsd_only}" = "1" ]]; then
		for i in "${!lst_audio_src[@]}"; do
			if [[ "${lst_audio_src[i]##*.}" != "dsf" ]]; then
					unset "lst_audio_src[$i]"
			fi
		done
	fi
	# Keep only WAVPACK if arg --wavpack_only
	if [[ "${wavpack_only}" = "1" ]]; then
		for i in "${!lst_audio_src[@]}"; do
			if [[ "${lst_audio_src[i]##*.}" != "wv" ]]; then
					unset "lst_audio_src[$i]"
			fi
		done
	fi
	# Keep only WAV if arg --wav_only
	if [[ "${wav_only}" = "1" ]]; then
		for i in "${!lst_audio_src[@]}"; do
			if [[ "${lst_audio_src[i]##*.}" != "wav" ]]; then
					unset "lst_audio_src[$i]"
			fi
		done
	fi
	# Keep only Monkey's Audio if arg --ape_only
	if [[ "${ape_only}" = "1" ]]; then
		for i in "${!lst_audio_src[@]}"; do
			if [[ "${lst_audio_src[i]##*.}" != "ape" ]]; then
					unset "lst_audio_src[$i]"
			fi
		done
	fi
	# Keep only ALAC codec among m4a files
	for i in "${!lst_audio_src[@]}"; do
		# Keep only ALAC codec among m4a files
		if [[ "${lst_audio_src[i]##*.}" = "m4a" ]]; then
			codec_test=$(ffprobe -v error -select_streams a:0 \
				-show_entries stream=codec_name -of csv=s=x:p=0 "${lst_audio_src[i]%.*}.m4a"  )
			if [[ "$codec_test" != "alac" ]]; then
				unset "lst_audio_src[$i]"
			fi
		fi
	done
fi

# Keep only 16 bits source if arg --16bits_only
if [[ "${bits16_only}" = "1" ]]; then
	for i in "${!lst_audio_src[@]}"; do
		codec_test=$(ffprobe -v error -select_streams a:0 \
			-show_entries stream=sample_fmt -of csv=s=x:p=0 "${lst_audio_src[i]}"  )
		if [[ "$codec_test" != "s16" ]] \
		&& [[ "$codec_test" != "s16p" ]]; then
			unset "lst_audio_src[$i]"
		fi
	done
fi
}
# Verify source integrity
test_source() {
local ape_test
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
	# FLAC - Verify integrity
	if [[ "$re_flac" = "1" ]] && [[ "${file##*.}" = "flac" ]]; then
		flac $flac_test_arg "$file" 2>"${cache_dir}/${file##*/}.decode_error.log"
	else
		# WAVPACK - Verify integrity
		if [[ "${file##*.}" = "wv" ]]; then
			wvunpack $wavpack_test_arg "$file" 2>"${cache_dir}/${file##*/}.decode_error.log"
		# APE - Verify integrity
		elif [[ "${file##*.}" = "ape" ]]; then
			mac "$file" -v 2>"${cache_dir}/${file##*/}.decode_error.log"
		# ALAC, DSD, WAV - Verify integrity
		elif [[ "${file##*.}" = "m4a" ]] || [[ "${file##*.}" = "wav" ]] || \
			 [[ "${file##*.}" = "dsf" ]]; then
			ffmpeg -v error -i "$file" -max_muxing_queue_size 9999 -f null - 2>"${cache_dir}/${file##*/}.decode_error.log"
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

	# APE - Special not support stderr
	if [[ "${file##*.}" = "ape" ]]; then
		ape_test=$(< "${cache_dir}/${file##*/}.decode_error.log" tail -1)
		if [[ "$ape_test" = "Success..." ]]; then
			rm "${cache_dir}/${file##*/}.decode_error.log"  2>/dev/null
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

decode_counter="0"

if [[ "$re_flac" != "1" ]]; then
	# APE - Decode
	for file in "${lst_audio_src_pass[@]}"; do
		if [[ "${file##*.}" = "ape" ]]; then
			(
			mac "$file" "${file%.*}.wav" -d &>/dev/null
			) &
			if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
				wait -n
			fi

			# Progress
			if ! [[ "$verbose" = "1" ]]; then
				decode_counter=$((decode_counter+1))
				if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
				else
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
				fi
			fi
		fi
	done
	wait

	# ALAC - Decode
	for file in "${lst_audio_src_pass[@]}"; do
		if [[ "${file##*.}" = "m4a" ]]; then
			(
			ffmpeg $ffmpeg_log_lvl -y -i "$file" "${file%.*}.wav"
			) &
			if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
				wait -n
			fi

			# Progress
			if ! [[ "$verbose" = "1" ]]; then
				decode_counter=$((decode_counter+1))
				if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
				else
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
				fi
			fi
		fi
	done
	wait

	# DSD - Decode
	for file in "${lst_audio_src_pass[@]}"; do
		if [[ "${file##*.}" = "dsf" ]]; then
			(
			ffmpeg $ffmpeg_log_lvl -y -i "$file" \
				-c:a pcm_s24le -ar 384000 "${file%.*}.wav"
			) &
			if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
				wait -n
			fi

			# Progress
			if ! [[ "$verbose" = "1" ]]; then
				decode_counter=$((decode_counter+1))
				if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
				else
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
				fi
			fi
		fi
	done
	wait

	# WAVPACK - Decode
	for file in "${lst_audio_src_pass[@]}"; do
		if [[ "${file##*.}" = "wv" ]]; then
			(
			wvunpack $wavpack_decode_arg "$file"
			) &
			if [[ $(jobs -r -p | wc -l) -ge $nproc ]]; then
				wait -n
			fi

			# Progress
			if ! [[ "$verbose" = "1" ]]; then
				decode_counter=$((decode_counter+1))
				if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source file decoded"\\r
				else
					echo -ne "${decode_counter}/${#lst_audio_src_pass[@]} source files decoded"\\r
				fi
			fi
		fi
	done
	wait
fi

# Progress end
if [[ "$verbose" != "1" ]];then
	if [[ "$re_flac" != "1" ]];then
		tput hpa 0; tput el
		if [[ "${#lst_audio_src_pass[@]}" = "1" ]]; then
			echo "${decode_counter} source file decoded"
		else
			echo "${decode_counter} source files decoded"
		fi
	fi
fi

# FLAC target array
for file in "${lst_audio_src_pass[@]}"; do
	if [[ "$re_flac" = "1" ]]; then
		lst_audio_wav_decoded+=( "${file%.*}.flac" )
	else
		lst_audio_wav_decoded+=( "${file%.*}.wav" )
	fi
done
}
# Convert tag to VORBIS
tags_2_flac() {
local cover_test
local cover_image_type
local cover_ext
local tag_label
local grab_tag_counter

grab_tag_counter="0"

for file in "${lst_audio_flac_compressed[@]}"; do

	# Reset
	source_tag=()
	source_tag_temp=()
	source_tag_temp1=()
	source_tag_temp2=()
	tag_name=()
	tag_label=()

	# FLAC
	if [[ "$re_flac" = "1" ]]; then
		if [[ -s "${file%.*}.flac" ]]; then
			# Source file tags array
			mapfile -t source_tag < <( metaflac "${file%.*}.flac" --export-tags-to=- )
			# Try to extract cover, if no cover in directory
			if [[ ! -e "${file%/*}"/cover.jpg ]] \
			&& [[ ! -e "${file%/*}"/cover.png ]]; then
				cover_test=$(metaflac --list "${file%.*}.flac" \
								| grep -A 8 METADATA 2>/dev/null \
								| grep -A 7 -B 1 PICTURE 2>/dev/null)
				if [[ -n "$cover_test" ]]; then
					# Image type
					cover_image_type=$(echo "$cover_test" | grep "MIME type" \
						| awk -F " " '{print $NF}' | awk -F "/" '{print $NF}'\
						| head -1)
					if [[ "$cover_image_type" = "png" ]]; then
						cover_ext="png"
					elif [[ "$cover_image_type" = "jpeg" ]]; then
						cover_ext="jpg"
					fi
					metaflac "${file%.*}.flac" \
						--export-picture-to="${file%/*}"/cover."$cover_ext"
				fi
			fi
		fi
	else

		# WAVPACK
		if [[ -s "${file%.*}.wv" ]]; then
			# Source file tags array
			mapfile -t source_tag_temp < <( wvtag -q -l "${file%.*}.wv" \
										| grep -v -e '^[[:space:]]*$' \
										| tail -n +2 | sort )
			# Clean array
			mapfile -t source_tag_temp1 < <( printf '%s\n' "${source_tag_temp[@]}" \
											| awk -F ":" '{print $1}' )
			mapfile -t source_tag_temp2 < <( printf '%s\n' "${source_tag_temp[@]}" \
											| cut -f2- -d':' | sed 's/^ *//' )
			for i in "${!source_tag_temp[@]}"; do
				source_tag+=( "${source_tag_temp1[$i]}=${source_tag_temp2[$i]}" )
			done

		# APE
		elif [[ -s "${file%.*}.ape" ]]; then
			# Source file tags array
			mapfile -t source_tag < <( ffprobe -v error -show_entries stream_tags:format_tags \
										-of default=noprint_wrappers=1 "${file%.*}.ape" )
			# Clean array
			for i in "${!source_tag[@]}"; do
				source_tag[$i]="${source_tag[$i]//TAG:/}"
			done
			# Try to extract cover, if no cover in directory
			if [[ ! -e "${file%/*}"/cover.jpg ]] \
			&& [[ ! -e "${file%/*}"/cover.png ]]; then
				cover_test=$(ffprobe -v error -select_streams v:0 \
							-show_entries stream=codec_name -of csv=s=x:p=0 "${file%.*}.ape")
				if [[ -n "$cover_test" ]]; then
					if [[ "$cover_test" = "png" ]]; then
						cover_ext="png"
					elif [[ "$cover_test" = *"jpeg"* ]]; then
						cover_ext="jpg"
					fi
					ffmpeg $ffmpeg_log_lvl -n -i "${file%.*}.ape" \
						"${file%/*}"/cover."$cover_ext" 2>/dev/null
				fi
			fi

		# ALAC
		elif [[ -s "${file%.*}.m4a" ]]; then
			# Source file tags array
			mapfile -t source_tag < <( ffprobe -v error -show_entries stream_tags:format_tags \
										-of default=noprint_wrappers=1 "${file%.*}.m4a" )
			# Clean array
			for i in "${!source_tag[@]}"; do
				source_tag[$i]="${source_tag[$i]//TAG:/}"
			done
			# Try to extract cover, if no cover in directory
			if [[ ! -e "${file%/*}"/cover.jpg ]] \
			&& [[ ! -e "${file%/*}"/cover.png ]]; then
				cover_test=$(ffprobe -v error -select_streams v:0 \
							-show_entries stream=codec_name -of csv=s=x:p=0 "${file%.*}.m4a")
				if [[ -n "$cover_test" ]]; then
					if [[ "$cover_test" = "png" ]]; then
						cover_ext="png"
					elif [[ "$cover_test" = *"jpeg"* ]]; then
						cover_ext="jpg"
					fi
					ffmpeg $ffmpeg_log_lvl -n -i "${file%.*}.m4a" \
						"${file%/*}"/cover."$cover_ext" 2>/dev/null
				fi
			fi

		# DSF
		elif [[ -s "${file%.*}.dsf" ]]; then
			# Source file tags array
			mapfile -t source_tag < <( ffprobe -v error -show_entries stream_tags:format_tags \
										-of default=noprint_wrappers=1 "${file%.*}.dsf" )
			# Clean array
			for i in "${!source_tag[@]}"; do
				source_tag[$i]="${source_tag[$i]//TAG:/}"
			done
			# Try to extract cover, if no cover in directory
			if [[ ! -e "${file%/*}"/cover.jpg ]] \
			&& [[ ! -e "${file%/*}"/cover.png ]]; then
				cover_test=$(ffprobe -v error -select_streams v:0 \
							-show_entries stream=codec_name -of csv=s=x:p=0 "${file%.*}.dsf")
				if [[ -n "$cover_test" ]]; then
					if [[ "$cover_test" = "png" ]]; then
						cover_ext="png"
					elif [[ "$cover_test" = *"jpeg"* ]]; then
						cover_ext="jpg"
					fi
					ffmpeg $ffmpeg_log_lvl -n -i "${file%.*}.dsf" \
						"${file%/*}"/cover."$cover_ext" 2>/dev/null
				fi
			fi

		fi
	fi

	# Remove empty tag label=
	mapfile -t source_tag < <( printf '%s\n' "${source_tag[@]}" | grep "=" )

	# Substitution
	for i in "${!source_tag[@]}"; do
		# MusicBrainz internal name
		source_tag[$i]="${source_tag[$i]//albumartistsort=/ALBUMARTISTSORT=}"
		source_tag[$i]="${source_tag[$i]//artistsort=/ARTISTSORT=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_artistid=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_albumid=/MUSICBRAINZ_ALBUMID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_artistid=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_releasegroupid=/MUSICBRAINZ_RELEASEGROUPID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_releasetrackid=/MUSICBRAINZ_RELEASETRACKID=}"
		source_tag[$i]="${source_tag[$i]//musicbrainz_trackid=/MUSICBRAINZ_RELEASETRACKID=}"
		source_tag[$i]="${source_tag[$i]//originalyear=/ORIGINALYEAR=}"
		source_tag[$i]="${source_tag[$i]//replaygain_album_gain=/REPLAYGAIN_ALBUM_GAIN=}"
		source_tag[$i]="${source_tag[$i]//replaygain_album_peak=/REPLAYGAIN_ALBUM_PEAK=}"
		source_tag[$i]="${source_tag[$i]//replaygain_track_gain=/REPLAYGAIN_TRACK_GAIN=}"
		source_tag[$i]="${source_tag[$i]//replaygain_track_peak=/REPLAYGAIN_TRACK_PEAK=}"

		# APEv2
		source_tag[$i]="${source_tag[$i]//Album Artist=/ALBUMARTIST=}"
		source_tag[$i]="${source_tag[$i]//Arranger=/ARRANGER=}"
		source_tag[$i]="${source_tag[$i]//Barcode=/BARCODE=}"
		source_tag[$i]="${source_tag[$i]//CatalogNumber=/CATALOGNUMBER=}"
		source_tag[$i]="${source_tag[$i]//Comment=/COMMENT=}"
		source_tag[$i]="${source_tag[$i]//Compilation=/COMPILATION=}"
		source_tag[$i]="${source_tag[$i]//Composer=/COMPOSER=}"
		source_tag[$i]="${source_tag[$i]//Conductor=/CONDUCTOR=}"
		source_tag[$i]="${source_tag[$i]//Copyright=/COPYRIGHT=}"
		source_tag[$i]="${source_tag[$i]//Year=/DATE=}"
		source_tag[$i]="${source_tag[$i]//Director=/DIRECTOR=}"
		source_tag[$i]="${source_tag[$i]//Disc=/DISCNUMBER=}"
		source_tag[$i]="${source_tag[$i]//DiscSubtitle=/DISCSUBTITLE=}"
		source_tag[$i]="${source_tag[$i]//DJMixer=/DJMIXER=}"
		source_tag[$i]="${source_tag[$i]//Engineer=/ENGINEER=}"
		source_tag[$i]="${source_tag[$i]//Genre=/GENRE=}"
		source_tag[$i]="${source_tag[$i]//Grouping=/GROUPING=}"
		source_tag[$i]="${source_tag[$i]//Label=/LABEL=}"
		source_tag[$i]="${source_tag[$i]//Language=/LANGUAGE=}"
		source_tag[$i]="${source_tag[$i]//Lyricist=/LYRICIST=}"
		source_tag[$i]="${source_tag[$i]//Lyrics=/LYRICS=}"
		source_tag[$i]="${source_tag[$i]//Media=/MEDIA=}"
		source_tag[$i]="${source_tag[$i]//Mixer=/MIXER=}"
		source_tag[$i]="${source_tag[$i]//Mood=/MOOD=}"
		source_tag[$i]="${source_tag[$i]//Performer=/PERFORMER=}"
		source_tag[$i]="${source_tag[$i]//MUSICBRAINZ_ALBUMSTATUS=/RELEASESTATUS=}"
		source_tag[$i]="${source_tag[$i]//MUSICBRAINZ_ALBUMTYPE=/RELEASETYPE=}"
		source_tag[$i]="${source_tag[$i]//MixArtist=/REMIXER=}"
		source_tag[$i]="${source_tag[$i]//Script=/SCRIPT=}"
		source_tag[$i]="${source_tag[$i]//Subtitle=/SUBTITLE=}"
		source_tag[$i]="${source_tag[$i]//Title=/TITLE=}"
		source_tag[$i]="${source_tag[$i]//Track=/TRACKNUMBER=}"
		source_tag[$i]="${source_tag[$i]//Weblink=/WEBSITE=}"
		source_tag[$i]="${source_tag[$i]//WEBSITE=/Weblink=}"
		source_tag[$i]="${source_tag[$i]//Writer=/WRITER=}"
		# ID3v2
		source_tag[$i]="${source_tag[$i]//Acoustid Id=/ACOUSTID_ID=}"
		source_tag[$i]="${source_tag[$i]//arranger=/ARRANGER=}"
		source_tag[$i]="${source_tag[$i]//description=/COMMENT=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Id=/MUSICBRAINZ_ALBUMID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Artist Id=/MUSICBRAINZ_ALBUMARTISTID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Status=/MUSICBRAINZ_ALBUMSTATUS=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Type=/MUSICBRAINZ_ALBUMTYPE=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Artist Id=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Artist Id=/MUSICBRAINZ_ARTISTID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Release Country=/RELEASECOUNTRY=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Release Group Id=/MUSICBRAINZ_RELEASEGROUPID=}"
		source_tag[$i]="${source_tag[$i]//MusicBrainz Release Track Id=/MUSICBRAINZ_RELEASETRACKID=}"
		source_tag[$i]="${source_tag[$i]//TBPM=/BPM=}"
		source_tag[$i]="${source_tag[$i]//TEXT=/LYRICIST=}"
		# iTune
		source_tag[$i]="${source_tag[$i]//MusicBrainz Album Artist Id=/MUSICBRAINZ_ALBUMARTISTID=}"
		# Waste fix
		source_tag[$i]="${source_tag[$i]//date=/DATE=}"
	done

	# Whitelist parsing
	mapfile -t tag_name < <( printf '%s\n' "${source_tag[@]}" | awk -F "=" '{print $1}' )
	mapfile -t tag_label < <( printf '%s\n' "${source_tag[@]}" | cut -f2- -d'=' )
	for i in "${!tag_name[@]}"; do
		for tag in "${Vorbis_whitelist[@]}"; do
			# Vorbis std
			if [[ "${tag_name[i],,}" = "${tag,,}" ]] \
			&& [[ -n "${tag_label[i]// }" ]]; then
				source_tag[$i]="${tag}=${tag_label[i]}"
				continue 2
			# reject
			else
				unset "source_tag[i]"
			fi
		done
	done

	# Add encoder ape tags
	source_tag+=( "ENCODEDBY=${flac_version}" )
	source_tag+=( "ENCODERSETTINGS=${flac_compress_arg}" )

	# Remove duplicate tags
	mapfile -t source_tag < <( printf '%s\n' "${source_tag[@]}" | sort -u )

	# Tag FLAC
	if [[ "$re_flac" = "1" ]]; then
		metaflac "$file" --remove-all
	fi
	for i in "${!source_tag[@]}"; do
		metaflac "$file" --set-tag="${source_tag[i]}"
	done

	# Progress
	if ! [[ "$verbose" = "1" ]]; then
		grab_tag_counter=$((grab_tag_counter+1))
		if [[ "${#lst_audio_flac_compressed[@]}" = "1" ]]; then
			echo -ne "${grab_tag_counter}/${#lst_audio_flac_compressed[@]} flac file is being tagged"\\r
		else
			echo -ne "${grab_tag_counter}/${#lst_audio_flac_compressed[@]} flac files are being tagged"\\r
		fi
	fi
done

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

for file in "${lst_audio_wav_decoded[@]}"; do
	# Compress FLAC
	(
	if [[ "$verbose" = "1" ]]; then
		flac $flac_compress_arg "$file"
	else
		flac $flac_compress_arg "$file" &>/dev/null
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
	# Array of ape target
	lst_audio_flac_compressed+=( "${lst_audio_wav_decoded[i]%.*}.flac" )

	# Remove temp wav files
	if [[ "${lst_audio_src[i]##*.}" != "wav" ]]; then
		rm -f "${lst_audio_src[i]%.*}.wav" 2>/dev/null
	fi
done
}
# Total size calculation in Mb - Input must be in bytes
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
# Display trick - print term tuncate
display_list_truncate() {
local list
local term_widh_truncate

list=("$@")

term_widh_truncate=$(stty size | awk '{print $2}' | awk '{ print $1 - 8 }')

for line in "${list[@]}"; do
	if [[ "${#line}" -gt "$term_widh_truncate" ]]; then
		echo -e "  $line" | cut -c 1-"$term_widh_truncate" | awk '{print $0"..."}'
	else
		echo -e "  $line"
	fi
done
}
# Summary of processing
summary_of_processing() {
local time_formated
local file_target_files_size
local file_diff_percentage
local file_path_truncate
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
			file_path_truncate=$(echo "${lst_audio_flac_compressed[i]}" | rev | cut -d'/' -f-3 | rev)
			filesPassLabel+=( "(${filesPassSizeReduction[i]}%) ~ .${file_path_truncate}" )
		done
	fi
	# All files rejected size label
	if (( "${#lst_audio_src_rejected[@]}" )); then
		for i in "${!lst_audio_src_rejected[@]}"; do
			file_path_truncate=$(echo "${lst_audio_src_rejected[i]}" | rev | cut -d'/' -f-3 | rev)
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
	echo "${#lst_audio_flac_compressed[@]}/${#lst_audio_src[@]} file(s) compressed to FLAC for a total of ${total_target_files_size}Mb."
	echo "${total_diff_percentage}% difference with the source files, ${total_diff_size}Mb on ${total_source_files_size}Mb."
	echo "Processing en: $(date +%D\ at\ %Hh%Mm) - Duration: ${time_formated}."
	echo
fi
}
# Remove source files
remove_source_files() {
if [[ "$re_flac" != "1" ]]; then
	if [ "${#lst_audio_flac_compressed[@]}" -gt 0 ] ; then
		read -r -p "Remove source files? [y/N]:" qarm
		case $qarm in
			"Y"|"y")
				# Remove source files
				for file in "${lst_audio_src_pass[@]}"; do
					rm -f "$file" 2>/dev/null
				done
			;;
			*)
				source_not_removed="1"
			;;
		esac
	fi
fi
}
# Remove target files
remove_target_files() {
if [ "$source_not_removed" = "1" ] ; then
	read -r -p "Remove target files? [y/N]:" qarm
	case $qarm in
		"Y"|"y")
			# Remove source files
			for file in "${lst_audio_flac_compressed[@]}"; do
				rm -f "$file" 2>/dev/null
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
if [[ "$command" = "mac" ]]; then
	command="$command (monkeys-audio package)"
fi
if [[ "$command" = "metaflac" ]]; then
	command="$command (flac package)"
fi
if [[ "$command" = "wvtag" ]] || [[ "$command" = "wavpack" ]]; then
	command="$command (wavpack package)"
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
  --16bits_only           Compress only 16bits source.
  --re_flac               Recompress FLAC source.
  --alac_only             Compress only ALAC source.
  --ape_only              Compress only Monkey's Audio source.
  --dsd_only              Compress only DSD source.
  --wav_only              Compress only WAV source.
  --wavpack_only          Compress only WAVPACK source.
  -v, --verbose           More verbose, for debug.

Supported source files:
  * ALAC as .m4a
  * DSD as .dsf
  * Monkey's Audio as .ape
  * WAVPACK as .wv
  * WAV as .wav
EOF
}

# Need Dependencies
core_dependencies=(ffmpeg ffprobe flac mac metaflac wavpack wvtag)
# Paths
export PATH=$PATH:/home/$USER/.local/bin
cache_dir="/tmp/2flac"
# Nb process parrallel (nb of processor)
nproc=$(grep -cE 'processor' /proc/cpuinfo)
# Input extention available
input_ext="ape|dsf|m4a|wv|wav"
# ALAC
ffmpeg_log_lvl="-hide_banner -loglevel panic -nostats"
# FLAC
flac_version=$(flac -v)
flac_test_arg="--no-md5-sum --no-warnings-as-errors -s -t"
flac_fix_arg="--totally-silent -f --verify --decode-through-errors"
flac_compress_arg="-f -8 -e -p"
# WAVPACK
wavpack_test_arg="-q -v"
wavpack_decode_arg="-q -w -y"
# Tag whitelist according with:
# https://picard-docs.musicbrainz.org/en/appendices/tag_mapping.html
# Ommit: ENCODEDBY, ENCODERSETTINGS = special case for rewrite this
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
	'REPLAYGAIN_ALBUM_GAIN'
	'REPLAYGAIN_ALBUM_PEAK'
	'REPLAYGAIN_ALBUM_RANGE'
	'REPLAYGAIN_REFERENCE_LOUDNESS'
	'REPLAYGAIN_TRACK_GAIN'
	'REPLAYGAIN_TRACK_PEAK'
	'REPLAYGAIN_TRACK_RANGE'
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

# Command arguments
while [[ $# -gt 0 ]]; do
	key="$1"
	case "$key" in
	-h|--help)
		usage
		exit
	;;
	"--16bits_only")
		bits16_only="1"
	;;
	"--re_flac")
		re_flac="1"
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

# Check cache directory
if [ ! -d "$cache_dir" ]; then
	mkdir "$cache_dir"
fi

# Consider if file exist in cache directory after 1 days, delete it
find "$cache_dir/" -type f -mtime +1 -exec /bin/rm -f {} \;

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

	# Compress
	compress_flac

	# Tag
	tags_2_flac

	# End
	summary_of_processing
	if (( "${#lst_audio_flac_compressed[@]}" )); then
		remove_source_files
		remove_target_files
	fi
fi
exit

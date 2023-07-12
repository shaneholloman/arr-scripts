#!/usr/bin/with-contenv bash
scriptVersion="1.0.5"
scriptName="Video"

#### Import Settings
source /config/extended.conf

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName :: $scriptVersion :: "$1
}

set -e
set -o pipefail

# auto-clean up log file to reduce space usage
if [ -f "/config/scripts/video.txt" ]; then
  find /config/scripts -type f -name "video.txt" -size +1024k -delete
fi

touch "/config/scripts/video.txt"
exec &> >(tee -a "/config/scripts/video.txt")

function Configuration {
	log "SABnzbd Job: $jobname"
	log "SABnzbd Category: $category"
	log "Script Versiion: $scriptVersion"
	log "CONFIGURATION VERIFICATION"
	log "##########################"
	log "Preferred Audio/Subtitle Languages: ${videoLanguages}"
	if [ "${requireLanguageMatch}" = "true" ]; then
		log "Require Matching Language :: Enabled"
	else
		log "Require Matching Language :: Disabled"
	fi
	
	if [ ${enableSma} = true ]; then
		log "Sickbeard MP4 Automator (SMA): ENABLED"
		if [ ${enableSmaTagging} = true ]; then
			tagging="-a"
			log "Sickbeard MP4 Automator (SMA): Tagging: ENABLED"
		else
			tagging="-nt"
			log "Sickbeard MP4 Automator (SMA): Tagging: DISABLED"
		fi
	else
		log "Sickbeard MP4 Automator (SMA): DISABLED"
	fi
	
	if [ -z "enableSmaTagging" ]; then
		enableSmaTagging=FALSE
	fi
}

VideoLanguageCheck () {

	count=0
	fileCount=$(find "$1" -type f -regex ".*/.*\.\(m4v\|wmv\|mkv\|mp4\|avi\)" | wc -l)
	log "Processing ${fileCount} video files..."
	find "$1" -type f -regex ".*/.*\.\(m4v\|wmv\|mkv\|mp4\|avi\)" -print0 | while IFS= read -r -d '' file; do
		count=$(($count+1))
		baseFileName="${file%.*}"
		fileName="$(basename "$file")"
		extension="${fileName##*.}"
		log "$count of $fileCount :: Processing $fileName"
		videoData=$(ffprobe -v quiet -print_format json -show_streams "$file")
		videoAudioTracksCount=$(echo "${videoData}" | jq -r ".streams[] | select(.codec_type==\"audio\") | .index" | wc -l)
		videoSubtitleTracksCount=$(echo "${videoData}" | jq -r ".streams[] | select(.codec_type==\"subtitle\") | .index" | wc -l)
		log "$count of $fileCount :: $videoAudioTracksCount Audio Tracks Found!"
		log "$count of $fileCount :: $videoSubtitleTracksCount Subtitle Tracks Found!"
		videoAudioLanguages=$(echo "${videoData}" | jq -r ".streams[] | select(.codec_type==\"audio\") | .tags.language")
		videoSubtitleLanguages=$(echo "${videoData}" | jq -r ".streams[] | select(.codec_type==\"subtitle\") | .tags.language")

		# Language Check
		log "$count of $fileCount :: Checking for preferred languages \"$videoLanguages\""
		preferredLanguage=false
		IFS=',' read -r -a filters <<< "$videoLanguages"
		for filter in "${filters[@]}"
		do
			videoAudioTracksLanguageCount=$(echo "${videoData}" | jq -r ".streams[] | select(.codec_type==\"audio\") | select(.tags.language==\"${filter}\") | .index" | wc -l)
			videoSubtitleTracksLanguageCount=$(echo "${videoData}" | jq -r ".streams[] | select(.codec_type==\"subtitle\") | select(.tags.language==\"${filter}\") | .index" | wc -l)
			log "$count of $fileCount :: $videoAudioTracksLanguageCount \"$filter\" Audio Tracks Found!"
			log "$count of $fileCount :: $videoSubtitleTracksLanguageCount \"$filter\" Subtitle Tracks Found!"			
			if [ "$preferredLanguage" == "false" ]; then
				if echo "$videoAudioLanguages" | grep -i "$filter" | read; then
					preferredLanguage=true
				elif echo "$videoSubtitleLanguages" | grep -i "$filter" | read; then
					preferredLanguage=true
				fi
			fi
		done

		if [ "$preferredLanguage" == "false" ]; then
			if [ ${enableSma} = true ]; then
				if [ "$smaProcessComplete" == "false" ]; then
					return
				fi
			fi
			if [ "$requireLanguageMatch" == "true" ]; then
				log "$count of $fileCount :: ERROR :: No matching languages found in $(($videoAudioTracksCount + $videoSubtitleTracksCount)) Audio/Subtitle tracks"
				log "$count of $fileCount :: ERROR :: Disable "
				rm "$file" && log "INFO: deleted: $fileName"
			fi
		fi

		
		
		log "$count of $fileCount :: Processing complete for: ${fileName}!"

	done

}

VideoFileCheck () {
	# check for video files
	if find "$1" -type f -regex ".*/.*\.\(m4v\|wmv\|mkv\|mp4\|avi\)" | read; then
		sleep 0.1
	else
		log "ERROR: No video files found for processing"
		exit 1
	fi
}

VideoSmaProcess (){
	count=0
	fileCount=$(find "$1" -type f -regex ".*/.*\.\(m4v\|wmv\|mkv\|mp4\|avi\)" | wc -l)
	log "Processing ${fileCount} video files..."
	find "$1" -type f -regex ".*/.*\.\(m4v\|wmv\|mkv\|mp4\|avi\)" -print0 | while IFS= read -r -d '' file; do
		count=$(($count+1))
		baseFileName="${file%.*}"
		fileName="$(basename "$file")"
		extension="${fileName##*.}"
		log "$count of $fileCount :: Processing $fileName"
		if [ -f "$file" ]; then	
			if [ -f /config/scripts/sma/config/sma.log ]; then
				rm /config/scripts/sma/config/sma.log
			fi
			log "$count of $fileCount :: Processing with SMA..."
			if [ -f "/config/scripts/sma.ini" ]; then
			
			# Manual run of Sickbeard MP4 Automator
				if python3 /config/scripts/sma/manual.py --config "/config/scripts/sma.ini" -i "$file" $tagging; then
					log "$count of $fileCount :: Complete!"
				else
					log "$count of $fileCount :: ERROR :: SMA Processing Error"
					rm "$file" && log "INFO: deleted: $fileName"
				fi
			else
				log "$count of $fileCount :: ERROR :: SMA Processing Error"
				log "$count of $fileCount :: ERROR :: \"/config/scripts/sma.ini\" configuration file is missing..."
				rm "$file" && log "INFO: deleted: $fileName"
			fi
		fi
	done
	smaProcessComplete="true"
}

function Main {
	SECONDS=0
	error=0
	folderpath="$1"
	jobname="$3"
	category="$5"
	smaProcessComplete="false"
	
	Configuration
	VideoFileCheck "$folderpath"
	VideoLanguageCheck "$folderpath"
	VideoFileCheck "$folderpath"
	if [ ${enableSma} = true ]; then
		VideoSmaProcess "$folderpath" "$category"
	fi
	VideoFileCheck "$folderpath"
	VideoLanguageCheck "$folderpath"	
	VideoFileCheck "$folderpath"

	duration=$SECONDS
	echo "Post Processing Completed in $(($duration / 60 )) minutes and $(($duration % 60 )) seconds!"
}


Main "$@" 

exit $?

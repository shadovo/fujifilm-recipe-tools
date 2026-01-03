#!/usr/bin/env bash

REQUIRED_EXIFTOOL_VERSION="10.50"
REQUIRED_MAGICK_VERSION="7.0"

validate_version() {
	local required_version="$1"
	local actual_version="$2"
	if [[ "$(printf '%s\n' "$required_version" "$actual_version" | sort -V | head -n1)" != "$required_version" ]]; then
		return 1
	fi
	return 0
}

if ! command -v exiftool &>/dev/null; then
	echo "Error: exiftool could not be found. Please install exiftool version $REQUIRED_EXIFTOOL_VERSION or later."
	exit 1
fi

INSTALLED_EXIFTOOL_VERSION="$(exiftool -ver)"
if ! validate_version "$REQUIRED_EXIFTOOL_VERSION" "$INSTALLED_EXIFTOOL_VERSION"; then
	echo "Error: exiftool version $INSTALLED_EXIFTOOL_VERSION is too old. Please install version $REQUIRED_EXIFTOOL_VERSION or later."
	exit 1
fi

if ! command -v magick &>/dev/null; then
	echo "Error: magick could not be found. Please install imagemagick version $REQUIRED_MAGICK_VERSION or later."
	exit 1
fi

INSTALLED_MAGICK_VERSION="$(magick --version | head -n1 | awk '{print $3}' | cut -d'-' -f1)"
if ! validate_version "$REQUIRED_MAGICK_VERSION" "$INSTALLED_MAGICK_VERSION"; then
	echo "Error: ImageMagick version $INSTALLED_MAGICK_VERSION is too old. Please install version $REQUIRED_MAGICK_VERSION or later."
	exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <path/to/fujifilm_image.jpg glob>"
	echo "Example: $0 *.jpg"
	exit 1
fi

ASCII_GREEN='\033[0;32m'
ASCII_GRAY='\033[2;37m'
ASCII_RED='\033[0;31m'
ASCII_ORANGE='\033[0;33m'
ASCII_RESET='\033[0m'

TOTAL_FILES_IN_GLOB=$#
total_created=0
total_skipped=0
total_failed=0

clear_status_line() {
	echo -ne "\r$(tput el)"
}

print_persisted_status() {
	local status=$1
	local file=$2
	local msg=$3
	clear_status_line
	case "$status" in
	"CREATED")
		echo -e "${ASCII_GREEN}[CREATED]${ASCII_RESET}\t$file\t$msg"
		;;
	"WARNING")
		echo -e "${ASCII_ORANGE}[WARNING]${ASCII_RESET}\t$file\t$msg"
		;;
	"ERROR")
		echo -e "${ASCII_RED}[ERROR]${ASCII_RESET}\t$file\t$msg"
		;;
	"SKIPPED")
		echo -e "${ASCII_GRAY}[SKIPPED]\t$file\t$msg${ASCII_RESET}"
		;;
	"*")
		echo -e "[$status]\t$file\t$msg\n"
		;;
	esac
}

SPINNER_PARTS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spinner_pid=

spinner_run() {
	local i=0
	while true; do
		i=$(((i + 1) % ${#SPINNER_PARTS[@]}))
		local spinner_char="${SPINNER_PARTS[$i]}"
		echo -ne "\r$spinner_char"
		sleep 0.1
	done
}

hide_cursor() {
	echo -ne "\033[?25l"
}

show_cursor() {
	echo -ne "\033[?25h"
}

display_status() {
	local status_msg="$1"
	local file_path="$2"
	local total_processed=$((total_created + total_skipped + total_failed))
	local progress="$total_processed/$TOTAL_FILES_IN_GLOB"
	echo -ne "\r$(tput el)⠿ [$progress] $status_msg: $file_path"
	sleep 0.01
}

print_summary() {
	local msg=$1
	local total_processed=$((total_created + total_skipped + total_failed))
	echo -e ""
	echo -e "$msg"
	echo -e "Files Processed: $total_processed of $TOTAL_FILES_IN_GLOB"
	echo -e "${ASCII_GREEN}[CREATED]: $total_created${ASCII_RESET}"
	if ((total_skipped != 0)); then
		echo -e "${ASCII_GRAY}[SKIPPED]: $total_skipped${ASCII_RESET}"
	fi
	if ((total_failed != 0)); then
		echo -e "${ASCII_RED}[FAILED]: $total_failed${ASCII_RESET}"
	fi
}

cleanup() {
	[[ -n "$spinner_pid" ]] && kill "$spinner_pid" &>/dev/null
	clear_status_line
	show_cursor
}

user_aborted() {
	print_summary "${ASCII_ORANGE}Aborted by user${ASCII_RESET}"
	exit 130
}

trap user_aborted SIGINT
trap cleanup EXIT
trap cleanup ERR

IMAGE_WIDTH=1080

COLUMN_GAP=28
COLUMN_WIDTH=$(((IMAGE_WIDTH - COLUMN_GAP) / 2))

FONT_SIZE=32

USER_COMMENT_VALUE="Created by: @shadovo/fujifilm-recipe-tools"

has_font() {
	local font_name="$1"
	if magick -list font 2>/dev/null | grep -q "^[[:space:]]*Font:[[:space:]]*${font_name}$"; then
		echo "$font_name"
		return 0
	else
		return 1
	fi
}

font_family=$(
	has_font "Futura-Bold" ||
		has_font "Arial-Bold" ||
		echo ""
)

apply_sign_fix() {
	local value="$1"
	local new_value=$value

	if [[ "$value" =~ ^[+-]?0$ ]]; then
		new_value="0"
	elif [[ "$value" =~ ^[+-] ]]; then
		new_value="$value"
	elif [[ "$value" =~ ^[0-9.] ]]; then
		new_value="+$value"
	fi

	echo "$new_value"
}

get_film_sim() {
	local film_sim="${exif_film_mode:-$exif_saturation}"

	case "$film_sim" in
	"F0/Standard (Provia)" | "F1/Studio Portrait" | "F1c/Studio Portrait Increased Sharpness")
		echo "Provia"
		;;
	"F1a/Studio Portrait Enhanced Saturation" | "F1b/Studio Portrait Smooth Skin Tone (Astia)" | "F3/Studio Portrait Ex")
		echo "Astia"
		;;
	"F2/Fujichrome (Velvia)" | "F4/Velvia")
		echo "Velvia"
		;;
	"Bleach Bypass")
		echo "Enterna Bleach Bypass"
		;;
	"Reala ACE")
		echo "Reala Ace"
		;;
	"None (B&W)")
		echo "Monochrome"
		;;
	"B&W Sepia")
		echo "Sepia"
		;;
	"B&W Red Filter" | "B&W Yellow Filter" | "B&W Green Filter")
		echo "${film_sim//B&W/Monochrome}"
		;;
	*)
		echo "$film_sim"
		;;
	esac
}

get_wb_fine_tune_scaled() {
	local red blue
	red="${exif_white_balance_fine_tune#* }"
	red="${red%%,*}"
	blue="${exif_white_balance_fine_tune##*, Blue }"
	printf "%s Red, %s Blue" "$(apply_sign_fix "$((red / 20))")" "$(apply_sign_fix "$((blue / 20))")"
}

get_monochromatic_color() {
	if ((exif_bw_adjustment || exif_bw_magenta_green)); then
		local wc mg
		wc="$(apply_sign_fix "${exif_bw_adjustment:-"0"}")"
		mg="$(apply_sign_fix "${exif_bw_magenta_green:-"0"}")"
		printf "%s WC, %s MG" "$wc" "$mg"
	fi
}

get_white_balance() {
	if [[ $exif_white_balance == "Kelvin" ]]; then
		echo "${exif_color_temperature}K"
	else
		echo "$exif_white_balance"
	fi
}

get_dynamic_range() {
	if [[ $exif_dynamic_range_setting == "Manual" ]]; then
		echo "DR$exif_development_dynamic_range"
	else
		echo "$exif_dynamic_range_setting"
	fi
}

get_grain_effect() {
	if [[ $exif_grain_effect_roughness == "Off" ]]; then
		echo "Off"
	else
		echo "$exif_grain_effect_roughness, $exif_grain_effect_size"
	fi
}

create_recipe_image() {

	local file_path file_dir file_base file_name file_output

	file_path="$1"
	file_dir=$(dirname "$file_path")
	file_base=$(basename "$file_path")
	file_name="${file_base%.*}"
	file_output="${file_dir}/${file_name}-recipe.jpg"

	while IFS=: read -r key value; do
		value="${value#"${value%%[![:space:]]*}"}"
		value="${value%"${value##*[![:space:]]*}"}"
		case "$key" in
		BWAdjustment) local exif_bw_adjustment="$value" ;;
		BWMagentaGreen) local exif_bw_magenta_green="$value" ;;
		Clarity) local exif_clarity="$value" ;;
		ColorChromeEffect) local exif_color_chrome_effect="$value" ;;
		ColorChromeFXBlue) local exif_color_chrome_fx_blue="$value" ;;
		ColorTemperature) local exif_color_temperature="$value" ;;
		DRangePriorityAuto) local exif_d_range_priority_auto="$value" ;;
		DevelopmentDynamicRange) local exif_development_dynamic_range="$value" ;;
		DynamicRangeSetting) local exif_dynamic_range_setting="$value" ;;
		FilmMode) local exif_film_mode="$value" ;;
		GrainEffectRoughness) local exif_grain_effect_roughness="$value" ;;
		GrainEffectSize) local exif_grain_effect_size="$value" ;;
		HighlightTone) local exif_highlight_tone="$value" ;;
		NoiseReduction) local exif_noise_reduction="$value" ;;
		Saturation) local exif_saturation="$value" ;;
		ShadowTone) local exif_shadow_tone="$value" ;;
		Sharpness) local exif_sharpness="$value" ;;
		UserComment) local exif_user_comment="$value" ;;
		WhiteBalance) local exif_white_balance="$value" ;;
		WhiteBalanceFineTune) local exif_white_balance_fine_tune="$value" ;;
		esac
	done <<EOF
$(
		exiftool -S \
			-BWAdjustment \
			-BWMagentaGreen \
			-Clarity \
			-ColorChromeEffect \
			-ColorChromeFXBlue \
			-ColorTemperature \
			-DRangePriorityAuto \
			-DevelopmentDynamicRange \
			-DynamicRangeSetting \
			-FilmMode \
			-FujiFilm:Sharpness \
			-GrainEffectRoughness \
			-GrainEffectSize \
			-HighlightTone \
			-NoiseReduction \
			-Saturation \
			-ShadowTone \
			-UserComment \
			-WhiteBalance \
			-WhiteBalanceFineTune \
			"$file_path" |
			sed -E "s/ \(((very|medium) )?(((hard|soft|high|low|strong|weak)(est)?)|normal)\)//g"
	)
EOF

	if [[ "$exif_user_comment" == *"$USER_COMMENT_VALUE"* ]]; then
		((total_skipped++))
		print_persisted_status "SKIPPED" "$file_path" "it is already a recipe image."
		return 0
	fi

	local labels values

	labels="Film Simulations:\n"
	values="$(get_film_sim)\n"

	labels+="White Balance:\n"
	values+="$(get_white_balance)\n"

	labels+="White Balance Shift:\n"
	values+="$(get_wb_fine_tune_scaled)\n"

	monochromatic_color="$(get_monochromatic_color)"
	if [[ ! $exif_saturation =~ .*(Acros|B\&W).* ]]; then
		labels+="Color:\n"
		values+="$(apply_sign_fix "$exif_saturation")\n"
	elif [[ -n $monochromatic_color ]]; then
		labels+="Monochromatic Color:\n"
		values+="$monochromatic_color\n"
	fi

	labels+="Highlight:\n"
	values+="$(apply_sign_fix "$exif_highlight_tone")\n"

	labels+="Shadow:\n"
	values+="$(apply_sign_fix "$exif_shadow_tone")\n"

	dynamic_range="$(get_dynamic_range)"
	if [[ -n $dynamic_range ]]; then
		labels+="Dynamic Range:\n"
		values+="$dynamic_range\n"
	elif [[ -n $exif_d_range_priority_auto ]]; then
		labels+="Dynamic Range Priority:\n"
		values+="$exif_d_range_priority_auto\n"
	fi

	labels+="Grain Effect:\n"
	values+="$(get_grain_effect)\n"

	labels+="Color Chrome Effect:\n"
	values+="$exif_color_chrome_effect\n"

	labels+="Color Chrome FX Blue:\n"
	values+="$exif_color_chrome_fx_blue\n"

	labels+="Sharpness:\n"
	values+="$(apply_sign_fix "$exif_sharpness")\n"

	labels+="Clarity:\n"
	values+="$(apply_sign_fix "$exif_clarity")\n"

	labels+="Noise Reduction:"
	values+="$exif_noise_reduction"

	if ! magick "$file_path" \
		-auto-orient \
		-resize "${IMAGE_WIDTH}x" \
		-blur 0x7 \
		-write mpr:BACKGROUND \
		+delete \
		\
		\( -background none \
		${font_family:+-font "$font_family"} \
		-pointsize "$FONT_SIZE" \
		-interline-spacing 0 \
		-fill white \
		\
		\( -size "${COLUMN_WIDTH}x" -gravity East caption:"$labels" \) \
		\( -size "${COLUMN_GAP}x%[fx:h]" xc:none \) \
		\( -size "${COLUMN_WIDTH}x" -gravity West caption:"$values" \) \
		\
		+append \
		-gravity Center \
		-write mpr:FOREGROUND \
		+delete \
		\) \
		\
		mpr:FOREGROUND \
		-fill "#00000080" \
		-colorize 100 \
		-blur 0x9 \
		-write mpr:SHADOW \
		+delete \
		\
		mpr:BACKGROUND \
		\
		mpr:SHADOW \
		-gravity Center \
		-compose Over -composite \
		\
		mpr:FOREGROUND \
		-gravity Center \
		-compose Over -composite \
		\
		"$file_output"; then

		((total_failed++))
		print_persisted_status "ERROR" "$file_output" "ImageMagick failed"
		return 1
	fi

	if exiftool -UserComment="$USER_COMMENT_VALUE" -overwrite_original "$file_output" &>/dev/null; then
		((total_created++))
		print_persisted_status "CREATED" "$file_output"
	else
		((total_failed++))
		print_persisted_status "ERROR" "$file_output" "failed to write custom tag to output"
	fi
}

echo ""
hide_cursor
spinner_run &
spinner_pid=$!

for file_path in "$@"; do

	full_file_path=$(printf '%q' "$PWD/$file_path")

	display_status "Processing" "$full_file_path"

	if [ ! -f "$full_file_path" ]; then
		((total_skipped++))
		print_persisted_status "WARNING" "$full_file_path" "not found or is not a regular file"
		continue
	fi

	if [[ "$(file -b --mime-type "$file_path")" != "image/jpeg" ]]; then
		((total_skipped++))
		print_persisted_status "WARNING" "$full_file_path" "is not a .jpg/.JPG file"
		continue
	fi

	create_recipe_image "$full_file_path"
done

print_summary "Finished"

#!/usr/bin/env bash

if ! command -v exiftool &>/dev/null; then
	echo "Error: exiftool could not be found. Please install it."
	exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <path/to/fujifilm_image.raf or .jpg>"
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "Error: File '$1' not found or is not a regular file."
	exit 1
fi

file_path="$1"
file_name="${file_path##*/}"

ansi_invert='\e[1;7m'
ansi_reset='\e[0m'

box_width=60
box_label_width=25

all_data=$(
	exiftool -s \
		-Make \
		-Model \
		-LensModel \
		\
		-FNumber \
		-ExposureTime \
		-ISO \
		-ExposureCompensation \
		-MeteringMode \
		-FocalLength \
		\
		-FilmMode -HighlightTone -ShadowTone -WhiteBalance -WhiteBalanceFineTune -Saturation \
		-Sharpness -NoiseReduction -DynamicRangeSetting -DevelopmentDynamicRange -GrainEffectRoughness -GrainEffectSize \
		-ColorChromeEffect -ColorChromeFXBlue -Clarity -ColorTemperature \
		"$file_path" |
		sed -E "s/\(((very|medium) )?(((soft|high|hard|weak)(est)?)|normal)\)//g"
)
get_value() {
	echo "$all_data" |
		grep -m 1 "^$1" |
		cut -d ':' -f 2- |
		xargs
}

get_film_sim() {
	local film_sim
	film_sim="$(get_value "FilmMode")"
	test -z "$film_sim" && film_sim=$(get_value "Saturation")

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

format_wb_fine_tune_scaled() {
	get_value "WhiteBalanceFineTune" | awk '{printf "Red %+d, Blue %+d", $2/20, $4/20}'
}

get_white_balance() {
	local wb
	wb="$(get_value "WhiteBalance")"
	if [[ $wb == "Kelvin" ]]; then
		echo "$(get_value "ColorTemperature")K"
	else
		echo "$wb"
	fi
}

get_dynamic_range() {
	local dr_type
	dr_type="$(get_value "DynamicRangeSetting")"
	if [[ $dr_type == "Manual" ]]; then
		echo "DR$(get_value "DevelopmentDynamicRange")"
	else
		echo "$dr_type"
	fi
}

get_grain_effect() {
	local grain_effect
	grain_effect="$(get_value "GrainEffectRoughness")"
	if [[ $grain_effect == "Off" ]]; then
		echo "Off"
	else
		echo "$grain_effect, $(get_value "GrainEffectSize")"
	fi
}

print_heading_line() {
	local heading="$1"
	local file_name="$2"
	local used_width=$((${#heading} + ${#file_name} + 6))
	local remaining_width=$((box_width - used_width))
	local border_segment
	border_segment=$(printf "%*s" $remaining_width)
	printf "╔${ansi_invert}%s %s %s${ansi_reset}╗\n" "$heading" "$border_segment" "$file_name"
}
print_section_divider() {
	local fill_width=$((box_width - 2))
	printf "╠%s╣\n" "$(printf "%*s" $fill_width | tr ' ' '═')"
}

print_section_heading_line() {
	local section_heading="$1"
	local heading_len=${#section_heading}
	local padding_needed=$((box_width - 5 - heading_len))
	printf "║ ${ansi_invert} %s ${ansi_reset}%*s║\n" "$section_heading" "$padding_needed" ""
}

print_data_line() {
	local label="$1"
	local raw_value="$2"
	local max_value_len=$((box_width - 5 - box_label_width))
	local value="$raw_value"
	if [ ${#raw_value} -gt $max_value_len ] && [ $max_value_len -ge 1 ]; then
		local truncate_len=$((max_value_len - 1))
		if [ $truncate_len -lt 0 ]; then
			truncate_len=0
		fi
		value="${raw_value:0:$truncate_len}…"
	fi
	local value_len=${#value}
	local padding_needed=$((box_width - 4 - box_label_width - value_len))
	if [ $padding_needed -lt 0 ]; then
		padding_needed=0
	fi
	printf "║ %-${box_label_width}s %s%*s║\n" "$label" "$value" $padding_needed ""
}

print_end_line() {
	local fill_width=$((box_width - 2))
	printf "╚%s╝\n" "$(printf "%*s" $fill_width | tr ' ' '═')"
}

camera_make=$(get_value "Make")
camera_model_full=$(get_value "Model")
camera_model_short=$(echo "$camera_model_full" | sed "s/$camera_make//i" | xargs)

color="$(get_value "Saturation")"

is_bw=false
if [[ $color =~ .*(Acros|B\&W).* ]]; then
	is_bw=true
fi

printf "\n"
print_heading_line "Fujifilm Recipe Card" "$file_name"
print_data_line "" ""
print_section_heading_line "Camera Gear"
print_data_line "Manufacturer" "$camera_make"
print_data_line "Camera Model" "$camera_model_short"
print_data_line "Lens" "$(get_value "LensModel")"
print_section_divider
print_section_heading_line "Camera settings"
print_data_line "Focal Length" "$(get_value "FocalLength")"
print_data_line "F Number" "$(get_value "FNumber")"
print_data_line "Shutter Speed" "$(get_value "ExposureTime")"
print_data_line "ISO" "$(get_value "ISO")"
print_data_line "Exposure Comp." "$(get_value "ExposureCompensation")"
print_data_line "Metering Mode" "$(get_value "MeteringMode")"
print_section_divider
print_section_heading_line "Recipe"
print_data_line "Film Simulation" "$(get_film_sim)"
print_data_line "White Balance" "$(get_white_balance)"
print_data_line "WB Shift" "$(format_wb_fine_tune_scaled)"
if ! $is_bw; then
	print_data_line "Color" "$color"
fi
print_data_line "Highlight" "$(get_value "HighlightTone")"
print_data_line "Shadow" "$(get_value "ShadowTone")"
print_data_line "Dynamic Range" "$(get_dynamic_range)"
print_data_line "Grain Effect" "$(get_grain_effect)"
print_data_line "Color Chrome Effect" "$(get_value "ColorChromeEffect")"
print_data_line "Color Chrome FX Blue" "$(get_value "ColorChromeFXBlue")"
print_data_line "Sharpness" "$(get_value "Sharpness")"
print_data_line "Clarity" "$(get_value "Clarity")"
print_data_line "Noise Reduction" "$(get_value "NoiseReduction")"
print_end_line

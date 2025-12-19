#!/usr/bin/env bash

if ! command -v exiftool &>/dev/null; then
	echo "Error: exiftool could not be found. Please install it."
	exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <path/to/fujifilm_image.raf or .jpg>"
	exit 1
fi

FILE_PATH="$1"
FILE_NAME="${FILE_PATH##*/}"

ALL_DATA=$(
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
		-Sharpness -NoiseReduction -DynamicRange -GrainEffectRoughness -GrainEffectSize \
		-ColorChromeEffect -ColorChromeFXBlue -Clarity \
		"$FILE_PATH"
)
function get_value() {
	echo "$ALL_DATA" | grep -m 1 "^$1" | awk -F ': ' '{$1=""; print $0}' | xargs
}

function format_wb_fine_tune_scaled() {
	local WB_FINE_TUNE_RAW
	WB_FINE_TUNE_RAW="$(get_value "WhiteBalanceFineTune")"
	echo "$WB_FINE_TUNE_RAW" | awk '{printf "%+d Red, %+d Blue", $2/20, $4/20}'
}
ANSI_INVERT='\e[1;7m'
ANSI_RESET='\e[0m'
BOX_WIDTH=60
LABEL_WIDTH=25

function print_heading_line() {
	local heading="$1"
	local file_name="$2"
	local used_width=$((${#heading} + ${#file_name} + 6))
	local remaining_width=$((BOX_WIDTH - used_width))
	local border_segment
	border_segment=$(printf "%*s" $remaining_width)
	printf "╔${ANSI_INVERT}%s %s %s${ANSI_RESET}╗\n" "$heading" "$border_segment" "$file_name"
}
function print_section_divider() {
	local fill_width=$((BOX_WIDTH - 2))
	printf "╠%s╣\n" "$(printf "%*s" $fill_width | tr ' ' '═')"
}

function print_section_heading_line() {
	local section_heading="$1"
	local heading_len=${#section_heading}
	local padding_needed=$((BOX_WIDTH - 5 - heading_len))
	printf "║ ${ANSI_INVERT} %s ${ANSI_RESET}%*s║\n" "$section_heading" "$padding_needed" ""
}

function print_data_line() {
	local label="$1"
	local raw_value="$2"
	local max_value_len=$((BOX_WIDTH - 5 - LABEL_WIDTH))
	local value="$raw_value"
	if [ ${#raw_value} -gt $max_value_len ] && [ $max_value_len -ge 1 ]; then
		local truncate_len=$((max_value_len - 1))
		if [ $truncate_len -lt 0 ]; then
			truncate_len=0
		fi
		value="${raw_value:0:$truncate_len}…"
	fi
	local value_len=${#value}
	local padding_needed=$((BOX_WIDTH - 4 - LABEL_WIDTH - value_len))
	if [ $padding_needed -lt 0 ]; then
		padding_needed=0
	fi
	printf "║ %-${LABEL_WIDTH}s %s%*s║\n" "$label" "$value" $padding_needed ""
}

function print_end_line() {
	local fill_width=$((BOX_WIDTH - 2))
	printf "╚%s╝\n" "$(printf "%*s" $fill_width | tr ' ' '═')"
}

MANUFACTURER=$(get_value "Make")
MODEL_FULL=$(get_value "Model")
MODEL_CLEAN=$(echo "$MODEL_FULL" | sed "s/$MANUFACTURER//i" | xargs)

printf "\n"
print_heading_line "Fujifilm Recipe Card" "$FILE_NAME"
print_data_line "" ""
print_section_heading_line "Camera Gear"
print_data_line "Manufacturer" "$MANUFACTURER"
print_data_line "Camera Model" "$MODEL_CLEAN"
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
print_data_line "Film Simulation" "$(get_value "FilmMode")"
print_data_line "White Balance" "$(get_value "WhiteBalance")"
print_data_line "WB Shift" "$(format_wb_fine_tune_scaled)"
print_data_line "Color" "$(get_value "Saturation")"
print_data_line "Highlight" "$(get_value "HighlightTone")"
print_data_line "Shadow" "$(get_value "ShadowTone")"
print_data_line "Dynamic Range" "$(get_value "DynamicRange")"
print_data_line "Grain Roughness" "$(get_value "GrainEffectRoughness")"
print_data_line "Grain Size" "$(get_value "GrainEffectSize")"
print_data_line "Color Chrome Effect" "$(get_value "ColorChromeEffect")"
print_data_line "Color Chrome FX Blue" "$(get_value "ColorChromeFXBlue")"
print_data_line "Sharpness" "$(get_value "Sharpness")"
print_data_line "Clarity" "$(get_value "Clarity")"
print_data_line "Noise Reduction" "$(get_value "NoiseReduction")"
print_end_line

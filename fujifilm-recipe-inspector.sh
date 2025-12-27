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

while IFS=: read -r key value; do
	value="${value#"${value%%[![:space:]]*}"}"
	case "$key" in
	Make) exif_make="$value" ;;
	Model) exif_model="$value" ;;
	LensModel) exif_lens_model="$value" ;;
	FNumber) exif_f_number="$value" ;;
	ExposureTime) exif_exposure_time="$value" ;;
	ISO) exif_iso="$value" ;;
	ExposureCompensation) exif_exposure_compensation="$value" ;;
	MeteringMode) exif_metering_mode="$value" ;;
	FocalLength) exif_focal_length="$value" ;;
	FilmMode) exif_film_mode="$value" ;;
	HighlightTone) exif_highlight_tone="$value" ;;
	ShadowTone) exif_shadow_tone="$value" ;;
	WhiteBalance) exif_white_balance="$value" ;;
	WhiteBalanceFineTune) exif_white_balance_fine_tune="$value" ;;
	Saturation) exif_saturation="$value" ;;
	Sharpness) exif_sharpness="$value" ;;
	NoiseReduction) exif_noise_reduction="$value" ;;
	DynamicRangeSetting) exif_dynamic_range_setting="$value" ;;
	DevelopmentDynamicRange) exif_development_dynamic_range="$value" ;;
	GrainEffectRoughness) exif_grain_effect_roughness="$value" ;;
	GrainEffectSize) exif_grain_effect_size="$value" ;;
	ColorChromeEffect) exif_color_chrome_effect="$value" ;;
	ColorChromeFXBlue) exif_color_chrome_fx_blue="$value" ;;
	Clarity) exif_clarity="$value" ;;
	ColorTemperature) exif_color_temperature="$value" ;;
	esac
done <<EOF
$(
	exiftool -S \
		-Make -Model -LensModel \
		-FNumber -ExposureTime -ISO -ExposureCompensation -MeteringMode -FocalLength \
		-FilmMode -HighlightTone -ShadowTone -WhiteBalance -WhiteBalanceFineTune -Saturation \
		-Sharpness -NoiseReduction -DynamicRangeSetting -DevelopmentDynamicRange -GrainEffectRoughness -GrainEffectSize \
		-ColorChromeEffect -ColorChromeFXBlue -Clarity -ColorTemperature \
		"$file_path" |
		sed -E "s/\(((very|medium) )?(((soft|high|hard|weak)(est)?)|normal)\)//g"
)
EOF

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

format_wb_fine_tune_scaled() {
	local red blue
	red="${exif_white_balance_fine_tune#* }"
	red="${red%%,*}"
	blue="${exif_white_balance_fine_tune##*, Blue }"
	printf "%+d Red, %+d Blue" $((red / 20)) $((blue / 20))
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

print_heading_line() {
	local heading="$1"
	local file_name="$2"
	local used_width=$((${#heading} + ${#file_name} + 6))
	local remaining_width=$((box_width - used_width))
	local border_segment
	border_segment=$(printf "%*s" $remaining_width)
	printf "\n╔${ansi_invert}%s %s %s${ansi_reset}╗\n" "$heading" "$border_segment" "$file_name"
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

print_heading_line "Fujifilm Recipe Card" "$file_name"
print_data_line "" ""
print_section_heading_line "Camera Gear"
print_data_line "Manufacturer" "$exif_make"
print_data_line "Camera Model" "${exif_model//$exif_make/}"
print_data_line "Lens" "$exif_lens_model"
print_section_divider
print_section_heading_line "Camera settings"
print_data_line "Focal Length" "$exif_focal_length"
print_data_line "F Number" "$exif_f_number"
print_data_line "Shutter Speed" "$exif_exposure_time"
print_data_line "ISO" "$exif_iso"
print_data_line "Exposure Comp." "$exif_exposure_compensation"
print_data_line "Metering Mode" "$exif_metering_mode"
print_section_divider
print_section_heading_line "Recipe"
print_data_line "Film Simulation" "$(get_film_sim)"
print_data_line "White Balance" "$(get_white_balance)"
print_data_line "WB Shift" "$(format_wb_fine_tune_scaled)"
if [[ ! $exif_saturation =~ .*(Acros|B\&W).* ]]; then
	print_data_line "Color" "$exif_saturation"
fi
print_data_line "Highlight" "$exif_highlight_tone"
print_data_line "Shadow" "$exif_shadow_tone"
print_data_line "Dynamic Range" "$(get_dynamic_range)"
print_data_line "Grain Effect" "$(get_grain_effect)"
print_data_line "Color Chrome Effect" "$exif_color_chrome_effect"
print_data_line "Color Chrome FX Blue" "$exif_color_chrome_fx_blue"
print_data_line "Sharpness" "$exif_sharpness"
print_data_line "Clarity" "$exif_clarity"
print_data_line "Noise Reduction" "$exif_noise_reduction"
print_end_line

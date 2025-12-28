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
	BWAdjustment) exif_bw_adjustment="$value" ;;
	BWMagentaGreen) exif_bw_magenta_green="$value" ;;
	Clarity) exif_clarity="$value" ;;
	ColorChromeEffect) exif_color_chrome_effect="$value" ;;
	ColorChromeFXBlue) exif_color_chrome_fx_blue="$value" ;;
	ColorTemperature) exif_color_temperature="$value" ;;
	DRangePriorityAuto) exif_d_range_priority_auto="$value" ;;
	DevelopmentDynamicRange) exif_development_dynamic_range="$value" ;;
	DynamicRangeSetting) exif_dynamic_range_setting="$value" ;;
	ExposureCompensation) exif_exposure_compensation="$value" ;;
	ExposureTime) exif_exposure_time="$value" ;;
	FNumber) exif_f_number="$value" ;;
	FilmMode) exif_film_mode="$value" ;;
	FocalLength) exif_focal_length="$value" ;;
	GrainEffectRoughness) exif_grain_effect_roughness="$value" ;;
	GrainEffectSize) exif_grain_effect_size="$value" ;;
	HighlightTone) exif_highlight_tone="$value" ;;
	ISO) exif_iso="$value" ;;
	LensModel) exif_lens_model="$value" ;;
	Make) exif_make="$value" ;;
	MeteringMode) exif_metering_mode="$value" ;;
	Model) exif_model="$value" ;;
	NoiseReduction) exif_noise_reduction="$value" ;;
	Saturation) exif_saturation="$value" ;;
	ShadowTone) exif_shadow_tone="$value" ;;
	Sharpness) exif_sharpness="$value" ;;
	WhiteBalance) exif_white_balance="$value" ;;
	WhiteBalanceFineTune) exif_white_balance_fine_tune="$value" ;;
	esac
done <<EOF
$(
	exiftool -S \
		-BWAdjustment \
		-BWMagentaGreen \
		-Clarity \
		-Clarity \
		-ColorChromeEffect \
		-ColorChromeFXBlue \
		-ColorTemperature \
		-DRangePriorityAuto \
		-DevelopmentDynamicRange \
		-DynamicRangeSetting \
		-ExposureCompensation \
		-ExposureTime \
		-FNumber \
		-FilmMode \
		-FocalLength \
		-FujiFilm:Sharpness \
		-GrainEffectRoughness \
		-GrainEffectSize \
		-HighlightTone \
		-ISO \
		-LensModel \
		-Make \
		-MeteringMode \
		-Model \
		-NoiseReduction \
		-Saturation \
		-ShadowTone \
		-WhiteBalance \
		-WhiteBalanceFineTune \
		"$file_path" |
		sed -E "s/ \(((very|medium) )?(((hard|soft|high|low|strong|weak)(est)?)|normal)\)//g"
)
EOF

apply_sign_fix() {
	local VALUE="$1"
	local NEW_VALUE=$VALUE

	if [[ "$VALUE" =~ ^[+-]?0$ ]]; then
		NEW_VALUE="0"
	elif [[ "$VALUE" =~ ^[+-] ]]; then
		NEW_VALUE="$VALUE"
	elif [[ "$VALUE" =~ ^[0-9.] ]]; then
		NEW_VALUE="+$VALUE"
	fi

	echo "$NEW_VALUE"
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
print_data_line "WB Shift" "$(get_wb_fine_tune_scaled)"

monochromatic_color="$(get_monochromatic_color)"
if [[ ! $exif_saturation =~ .*(Acros|B\&W).* ]]; then
	print_data_line "Color" "$exif_saturation"
elif [[ -n $monochromatic_color ]]; then
	print_data_line "Monochromatic Color" "$monochromatic_color"
fi

print_data_line "Highlight" "$(apply_sign_fix "$exif_highlight_tone")"
print_data_line "Shadow" "$(apply_sign_fix "$exif_shadow_tone")"

dynamic_range="$(get_dynamic_range)"
if [[ -n $dynamic_range ]]; then
	print_data_line "Dynamic Range" "$dynamic_range"
elif [[ -n $exif_d_range_priority_auto ]]; then
	print_data_line "Dynamic Range Priority" "$exif_d_range_priority_auto"
fi
print_data_line "Grain Effect" "$(get_grain_effect)"
print_data_line "Color Chrome Effect" "$exif_color_chrome_effect"
print_data_line "Color Chrome FX Blue" "$exif_color_chrome_fx_blue"
print_data_line "Sharpness" "$(apply_sign_fix "$exif_sharpness")"
print_data_line "Clarity" "$(apply_sign_fix "$exif_clarity")"
print_data_line "Noise Reduction" "$(apply_sign_fix "$exif_noise_reduction")"
print_end_line

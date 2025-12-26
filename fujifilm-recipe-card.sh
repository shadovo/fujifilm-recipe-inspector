#!/usr/bin/env bash

if ! command -v exiftool &>/dev/null; then
	echo "Error: exiftool could not be found. Please install it."
	exit 1
fi

if ! command -v magick &>/dev/null; then
	echo "Error: magick could not be found. Please install imagemagick."
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
file_dir=$(dirname "$file_path")
file_base=$(basename "$file_path")
file_name="${file_base%.*}"
file_output="${file_dir}/${file_name}-recipe.jpg"

image_width=1080

column_gap=28
column_width=$(((image_width - column_gap) / 2))

font_size=32
font_family=""

has_font() {
	local font_name=$1
	if identify -list font 2>/dev/null | grep -q "^[[:space:]]*Font:[[:space:]]*${font_name}$"; then
		echo "$font_name"
		return 0
	else
		return 1
	fi
}

font_family=$(
	has_font "Futura-Bold" ||
		has_font "Helvetica-Bold" ||
		has_font "Arial-Bold" ||
		echo ""
)

all_data=$(
	exiftool -s \
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
	get_value "WhiteBalanceFineTune" | awk '{printf "%+d Red & %+d Blue", $2/20, $4/20}'
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

color="$(get_value "Saturation")"

is_bw=false
if [[ $color =~ .*(Acros|B\&W).* ]]; then
	is_bw=true
fi

labels="Film simulations:\n"
values="$(get_film_sim)\n"

labels+="White Balance:\n"
values+="$(get_white_balance)\n"

labels+="White Balance Shift:\n"
values+="$(format_wb_fine_tune_scaled)\n"

if ! $is_bw; then
	labels+="Color:\n"
	values+="$color\n"
fi

labels+="Highlight:\n"
values+="$(get_value "HighlightTone")\n"

labels+="Shadow:\n"
values+="$(get_value "ShadowTone")\n"

labels+="Dynamic Range:\n"
values+="$(get_dynamic_range)\n"

labels+="Grain Effect:\n"
values+="$(get_grain_effect)\n"

labels+="Color Chrome Effect:\n"
values+="$(get_value "ColorChromeEffect")\n"

labels+="Color Chrome FX Blue:\n"
values+="$(get_value "ColorChromeFXBlue")\n"

labels+="Sharpness:\n"
values+="$(get_value "Sharpness")\n"

labels+="Clarity:\n"
values+="$(get_value "Clarity")\n"

labels+="Noise Reduction:"
values+="$(get_value "NoiseReduction")"

caption_block=(
	"(" -size "${column_width}"x -gravity East caption:"${labels}" ")"
	"(" -size "${column_gap}"x%[fx:h] xc:none ")"
	"(" -size "${column_width}"x -gravity West caption:"${values}" ")"
)

magick "$file_path" \
	-auto-orient \
	-resize "${image_width}x" \
	-blur 0x7 \
	\
	\( -background none \
	${font_family:+-font "$font_family"} \
	-pointsize "$font_size" \
	-interline-spacing 0 \
	-stroke black \
	-fill white \
	\
	"${caption_block[@]}" \
	\
	+append \
	-gravity Center \
	\) \
	\
	-gravity Center \
	-compose Over -composite \
	"$file_output"

echo "Created $file_output"

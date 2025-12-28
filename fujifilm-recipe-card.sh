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

has_font() {
	local font_name="$1"
	if identify -list font 2>/dev/null | grep -q "^[[:space:]]*Font:[[:space:]]*${font_name}$"; then
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
	FilmMode) exif_film_mode="$value" ;;
	GrainEffectRoughness) exif_grain_effect_roughness="$value" ;;
	GrainEffectSize) exif_grain_effect_size="$value" ;;
	HighlightTone) exif_highlight_tone="$value" ;;
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

magick "$file_path" \
	-auto-orient \
	-resize "${image_width}x" \
	-blur 0x7 \
	-write mpr:BACKGROUND \
	+delete \
	\
	\( -background none \
	${font_family:+-font "$font_family"} \
	-pointsize "$font_size" \
	-interline-spacing 0 \
	-fill white \
	\
	\( -size "${column_width}x" -gravity East caption:"$labels" \) \
	\( -size "${column_gap}x%[fx:h]" xc:none \) \
	\( -size "${column_width}x" -gravity West caption:"$values" \) \
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
	"$file_output"

echo "Created $file_output"

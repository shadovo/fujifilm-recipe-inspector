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
	echo "Usage: $0 <path/to/fujifilm_image.jpg glob>"
	echo "Example: $0 *.jpg"
	exit 1
fi

cleanup_and_exit() {
	echo ""
	echo "Script cancelled by user. Exiting immediately."
	exit 130
}

trap cleanup_and_exit SIGINT

image_width=1080

column_gap=28
column_width=$(((image_width - column_gap) / 2))

font_size=32

user_comment_value="Created by: @shadovo/fujifilm-recipe-tools"

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
	file_output="${file_dir}/${file_name}-recipe.JPG"

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

	if [[ "$exif_user_comment" == *"$user_comment_value"* ]]; then
		echo "   Skipping file '$file_path' because it is already a recipe image."
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

	if ! exiftool -UserComment="$user_comment_value" -overwrite_original "$file_output" &>/dev/null; then
		echo "🔴 Error: Failed to write custom tag to output file: $file_output"
	fi

	echo "🟢 Created $file_output"
}

for file_path in "$@"; do

	echo "🔵 Processing $file_path"

	if [ ! -f "$file_path" ]; then
		echo "🟠 Warning: File '$file_path' not found or is not a regular file. Skipping."
		continue
	fi

	if [[ "$file_path" != *.jpg && "$file_path" != *.JPG ]]; then
		echo "🟠 Warning: File '$file_path' is not a .jpg file. Skipping."
		continue
	fi

	create_recipe_image "$file_path"
done

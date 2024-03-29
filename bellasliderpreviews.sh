#!/bin/bash

# If .besp and .bsa files already exist, there is the option to NOT overwrite them and to 
# generate a new index 

if [ -z ${BELLA_VERSION} ]; then
	BELLA_VERSION="23.6.0"
fi

BESP_MODE="generate_besp"
bellaOrbitDegrees=0
#bellaGroup="material"
bellaGroup="geometry"
#bellaGroup="moo"
bellaMaterials=( "blend" "carPaint" "conductor" "dielectric" "emitterProjector" "emitter" "orenNayer" "quickMaterial" )
#bellaSpecial=( "xform" "box" "sphere" "volumetricMaterial" "polygon")

# Note all bash vars are global, except local
#============================================
function func_multiply () {
    func_multiply_return=$(awk -v X=$1 -v Y=$2 \
        'BEGIN{ 
                result = X*Y; 
                printf "%f", result}'
    )
}

function func_add () {
    func_add_return=$(awk -v X=$1 -v Y=$2 \
        'BEGIN{ 
                result = X+Y; 
                printf "%f", result}'
    )
}

# expect frames starting at 1
function func_lerp () {
	func_lerp_result=$(awk -v "startVal=$1" -v "endVal=$2" -v "currentFrame=$3" -v "totalFrames=$4" \
    'BEGIN {print ((endVal-(startVal))*((currentFrame-1)/(totalFrames-1)))+(startVal)}')
}

function anim_angle_to_mat4() {
    func_anim_angle_to_mat4_return=$(awk -v angle=$1 -v currentStep=$2  -v totalSteps=$3 \
        'BEGIN{ 
                PI=3.14159265
                elemA = cos(((angle/totalSteps)*(currentStep-1))/180*PI); 
                elemB = sin(((angle/totalSteps)*(currentStep-1))/180*PI); 
                elemC = sin(((angle/totalSteps)*(currentStep-1))/180*PI)*-1; 
                elemD = cos(((angle/totalSteps)*(currentStep-1))/180*PI); 
                printf "%f %f 0 0 %f %f 0 0 0 0 1 0 0 0 0 1", elemA, elemB, elemC, elemD }'
        ) 
}

# convert angle to mat4
#anim_angle_to_mat4 $angle 15 30
#rotationMat4=(${func_anim_angle_to_mat4_return})
#echo ${#rotMat4[@]}

# bash 3.2 on MacOS does not support associative arrays

# using map array since we lack associative arrays
func_dot_product_mat4 () {
    # convert angle to mat4
    anim_angle_to_mat4 $1 $2 $3
    local rotationMat4=(${func_anim_angle_to_mat4_return})
    resultingMat4=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
    local linearIndexMap=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
    local skipIndexMap=(0 4 8 12 1 5 9 13 2 6 10 14 3 7 11 15)

    local firstOffset=0
    local secondOffset=0
    local fourCount=0
    # walk every row, every column, do dot product math
    for (( ixx = 0 ; ixx < 16 ; ixx++ )); do
        for ((colCount = 0 ; colCount < 4 ; colCount++ )); do
            #echo "${ixx} ${linearIndexMap[$((colCount+firstOffset))]} ${skipIndexMap[$((colCount+secondOffset))]}"
            camIndex=${linearIndexMap[$((colCount+firstOffset))]} 
            rotationIndex=${skipIndexMap[$((colCount+secondOffset))]}
            func_multiply ${camMat4[ $camIndex ]} ${rotationMat4[ $rotationIndex ]}
            func_add ${resultingMat4[$ixx]} $func_multiply_return
            resultingMat4[$ixx]=$func_add_return
        done
        secondOffset=$((secondOffset+4))
        fourCount=$((fourCount+1))
        if [ $fourCount == 4 ]; then
            fourCount=0
            firstOffset=$((firstOffset+4))
            secondOffset=0
        fi
    done
}

function bella_rgba_to_arr () {
    local localrgb=$1
    result="${localrgb#rgba\(*}"
    result="${result%*\)}"
    func_bella_rgba_to_arr_return=($result)
}

if test -d ${BELLA_VERSION}; then
	echo -e "\nFound existing .besp and .bsa files"
	scene_files=${BELLA_VERSION}/${bellaGroup}/*.besp
	select anim in overwrite_existing_besp render_existing_besp quit
	do
		break
	done
	if [ $REPLY == "1" ]; then
		rm -f ${BELLA_VERSION}/${bellaGroup}/*.besp
		rm -f ${BELLA_VERSION}/${bellaGroup}/*.bsa
		BESP_MODE="generate_besp"
	elif [ $anim == "quit" ]; then
		exit
	else
		BESP_MODE="render_existing_besp"
	fi
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
	bella_cli_path="/Applications/bella_cli.app/Contents/MacOS/bella_cli"
	os_name="MacOS"
elif [[ "$OSTYPE" == "msys"* ]]; then
	bella_cli_path="C:/Program Files/Diffuse Logic/Bella CLI/bella_cli.exe"
	os_name="Windows"
else
	os_name=$(awk -F= '$1=="NAME" { print $2 ;}' /etc/os-release)
	platform_id=$(awk -F= '$1=="PLATFORM_ID" { print $2 ;}' /etc/os-release)
	bella_cli_path="./bella_cli"
	if ! test -f bella_cli; then
		# RHEL 8.x and 9.x 
		if [ "$platform_id" == "\"platform:el8\"" ] || [ "$platform_id" == "\"platform:el9\"" ]; then
			sudo dnf -y install mesa-vulkan-drivers
			sudo dnf -y install mesa-libGL
		#  Debian based
		else
			sudo apt -y update
			sudo apt -y install mesa-vulkan-drivers
			sudo apt -y install libgl1-mesa-glx
		fi
		curl -O https://downloads.bellarender.com/bella_cli-${BELLA_VERSION}.tar.gz
		tar -xvf bella_cli-${BELLA_VERSION}.tar.gz
	fi
fi
if ! test -f "${bella_cli_path}"; then
	echo "FAIL: ${bella_cli_path} does not exist"
	exit
fi

file_ext="jpg"
bsa64=""
anim64=""

if [ $BESP_MODE == "generate_besp" ]; then
	scene_files=*.bs*
	select scene in ${scene_files} quit
	do
		break
	done
	if ! [ ${scene} == "quit" ]; then
		echo "$REPLY $scene"
	else
		exit
	fi

	#echo -e "\nbellasliderpreview.sh will render using bella_cli to generate scrubbeable previews"
	#echo "This supplements the bella docs with visual feedback on how each attribute affects the render"

	#echo -e "\nSelect a premade set of slider preview animations to render"
	#echo "Your scene will locally render 30 frames for each attribute, meaning this will take a long time"
	#select bellaGroup in all environment camera light geometry material quit
	#do
	#	break
	#done
fi

idle="1"

# Common toplevel dir for intermediate files, a subdir called render_html_dir will store html and jpg
render_besp_dir="${BELLA_VERSION}/${bellaGroup}"
mkdir -p ${render_besp_dir}

# GENERATE PASS, converts templates to useable besp
if [ $BESP_MODE == "generate_besp" ]; then
	# Get list of all template .besp files
	template_files=templates_besp/${bellaGroup}/*.besp
	unset node_name
	# Loop over template files
	for each_template in $template_files; do
		bellaOrbitDegrees=0
		template_basename="$(basename "$each_template")"
		template_besp_dir="$(dirname "$each_template")"
		template_uuid=${template_basename%.*} 
		#echo "GEN BASE $template_basename DIR $template_besp_dir UUID $template_uuid SCENE $scene"

        ####
        stepIndex=0
        unset bellaFragment
        unset bespNode
        unset bespNodeName
		stepFragmentIndex=0
		stepSelectIndex=0
		bespNodeIndex=0
        while read each_line; do
            if ! [[ -z ${each_line} ]] && ! [[ ${each_line:0:1} == "#" ]]; then
                less_trailing_whitespace="$(sed -e 's/[[:space:]]*$//' <<<${each_line})"
                if ! [[ -z ${less_trailing_whitespace} ]] ; then
					# parseFragments can contains strings that break bash 
					# like brackets, requiring that fragment strings are caught first
					# before being used in a bash parameter expansion
                    if [ ${less_trailing_whitespace%Fragment=*} == "bella" ] ; then
                        bellaFragment[${stepFragmentIndex}]=${less_trailing_whitespace#*bellaFragment=} 
                        stepFragmentIndex=$((stepFragmentIndex+1))
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderStart" ] ; then
                        bellaSliderStart=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderEnd" ] ; then
                        bellaSliderEnd=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderType" ] ; then
                        bellaSliderType=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderFrames" ] ; then
                        bellaSliderFrames=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaOrbitDegrees" ] ; then
                        bellaOrbitDegrees=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaNodeType" ] ; then
                        bellaNodeType=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaNode" ] ; then
                        bellaNode=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaUnits" ] ; then
                        bellaUnits=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaScene" ] ; then
                        bellaScene=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaNodeAttribute" ] ; then
                        bellaNodeAttribute=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderNode" ] ; then
                        bellaSliderNode=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace:0:4} == "besp" ] ; then
                        bespNode[${bespNodeIndex}]=${less_trailing_whitespace#*besp*=} 
                        bespNodeName[${bespNodeIndex}]="${less_trailing_whitespace%=*}"
                        bespNodeIndex=$((bespNodeIndex+1))
                    elif [ ${less_trailing_whitespace%=*} == "selectXform" ] ; then
                        selectXform=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectMesh" ] ; then
                        selectMesh=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectMaterial" ] ; then
                        selectMaterial=${less_trailing_whitespace#*=} 

                    fi
                fi
            fi
        done <${each_template}


		if [ -z $selectXform ]; then
			echo -e "\n===\nSelect xform to assign to variable \$selectXform"
			select_nodes=$("${bella_cli_path}" -ln:"xform" -i:${scene})
			node_names_with_spaces="${select_nodes//,/ }"
			select selectXform in $node_names_with_spaces
			do
				break
			done
			echo -e "\n===\nSelect camera xform to assign to variable \$selectCameraXform"
			select_nodes=$("${bella_cli_path}" -ln:"xform" -i:${scene})
			node_names_with_spaces="${select_nodes//,/ }"
			select selectCameraXform in $node_names_with_spaces
			do
				break
			done
			bellaCameraXform=$("${bella_cli_path}" -qa:"$selectCameraXform.steps[0].xform" -i:${scene})
			echo $bellaCameraXform
			temp4=$(sed -e 's/mat4(//' <<<${bellaCameraXform})	
			camMat4=($(sed -e 's/)//' <<<${temp4}))

			echo -e "\n===\nSelect mesh to assign to variable \$selectMesh"
			select_nodes=$("${bella_cli_path}" -ln:"mesh" -i:${scene})
			node_names_with_spaces="${select_nodes//,/ }"
			select selectMesh in $node_names_with_spaces
			do
				break
			done

			echo -e "\n===\nSelect material to assign to variable \$selectMesh"
			select_nodes=$("${bella_cli_path}" -ln:"material" -i:${scene})
			node_names_with_spaces="${select_nodes//,/ }"
			select selectMaterial in $node_names_with_spaces
			do
				break
			done
		fi

        echo "bellaSliderStart=${bellaSliderStart}" > ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaSliderEnd=${bellaSliderEnd}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaSliderFrames=${bellaSliderFrames}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaOrbitDegrees=${bellaOrbitDegrees}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
		for ((i = 0 ; i < ${#bespNode[@]} ; i++ )); do
        	echo "${bespNodeName[${i}]}=${bespNode[$i]}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
		done
        echo "bellaScene=${scene}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaSliderType=${bellaSliderType}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaSliderNode=${bellaSliderNode}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaNodeType=${bellaNodeType}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaNode=${bellaNode}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaNodeAttribute=${bellaNodeAttribute}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaUnits=${bellaUnits}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "selectMesh=${selectMesh}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "selectXform=${selectXform}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "selectMaterial=${selectMaterial}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "selectCameraXform=${selectCameraXform}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "camMat4=${camMat4[@]}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp

        #rm -f  ${render_besp_dir}/${scene}.${template_uuid}.bsa
        for ((i = 0 ; i < ${#bellaFragment[@]} ; i++ )); do
        	echo "bellaFragment=${bellaFragment[$i]}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        done
        echo -e "\n" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
	done
fi


# COMMON PASS
if [ ${idle} == "1" ]; then
	# Get list of all besp files to be processed
	besp_files=$BELLA_VERSION/${bellaGroup}/*.besp
	# Init directory.html
	cat templates_html/predirectory.html > ./${BELLA_VERSION}/${bellaGroup}/directory.html

	for each_besp in $besp_files; do
		bellaOrbitDegrees=0
		# Get filename without leading path
		render_basename="$(basename "$each_besp")"
		# Get parent path
		render_besp_dir="$(dirname "$each_besp")"
		if grep -q ".bsz." <<< "$render_basename"; then
			bella_scene="${render_basename%.bsz.*}.bsz"
		elif grep -q ".bsx." <<< "$render_basename"; then
			bella_scene="${render_basename%.bsx.*}.bsx"
		else		
			bella_scene="${render_basename%.bsa.*}.bsa"
		fi
		# Removing .besp extension should provide useful uuid
		render_uuid=${render_basename%.*} 
		render_html_dir="${render_besp_dir}/${render_uuid}"
		mkdir -p ${render_html_dir}
		#echo "EXIST BASE $render_basename DIR $render_besp_dir UUID $render_uuid SCENE $bella_scene"

        stepFragmentIndex=0
        stepSelectIndex=0
        bespNodeIndex=0
        unset bespNode
        unset bespNodeName
        unset bellaFragment
		unset insert0
		unset insert1
        while read each_line; do
            if ! [[ -z ${each_line} ]]; then
                less_trailing_whitespace="$(sed -e 's/[[:space:]]*$//' <<<${each_line})"
                if ! [[ -z ${less_trailing_whitespace} ]]; then
                    if [ ${less_trailing_whitespace%=*} == "bellaSliderStart" ] ; then
                        bellaSliderStart=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderEnd" ] ; then
                        bellaSliderEnd=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderType" ] ; then
                        bellaSliderType=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderFrames" ] ; then
                        bellaSliderFrames=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaOrbitDegrees" ] ; then
                        bellaOrbitDegrees=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaNodeType" ] ; then
                        bellaNodeType=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaNode" ] ; then
                        bellaNode=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaUnits" ] ; then
                        bellaUnits=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaScene" ] ; then
                        bellaScene=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaNodeAttribute" ] ; then
                        bellaNodeAttribute=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "bellaSliderNode" ] ; then
                        bellaSliderNode=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%Fragment=*} == "bella" ] ; then
                        bellaFragment[${stepFragmentIndex}]=${less_trailing_whitespace#*bellaFragment=} 
                        stepFragmentIndex=$((stepFragmentIndex+1))
                    elif [ ${less_trailing_whitespace:0:4} == "besp" ] ; then
                        bespNode[${bespNodeIndex}]=${less_trailing_whitespace#*besp*=} 
                        bespNodeName[${bespNodeIndex}]=${less_trailing_whitespace%=*} 
                        bespNodeIndex=$((bespNodeIndex+1))
                    elif [ ${less_trailing_whitespace%=*} == "selectMesh" ] ; then
                        selectMesh=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectXform" ] ; then
                        selectXform=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectCameraXform" ] ; then
                        selectCameraXform=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectMaterial" ] ; then
                        selectMaterial=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "camMat4" ] ; then
                        camMat4=(${less_trailing_whitespace#*=})
                    fi
                fi
            fi
        done <${each_besp}

		# bella.js
    	echo "bellaScene=\"${bella_scene}\";" > ${render_html_dir}/bella.js
    	echo "bellaNodeType=\"${bellaNodeType}\";" >> ${render_html_dir}/bella.js
    	echo "bellaNode=\"${bellaNode}\";" >> ${render_html_dir}/bella.js
    	echo "bellaNodeAttribute=\"${bellaNodeAttribute}\";" >> ${render_html_dir}/bella.js
		echo "bellaSteps=[];" >> ${render_html_dir}/bella.js
		echo "bellaQueue=[];" >> ${render_html_dir}/bella.js

		# html
		cp ./templates_html/template.html ${render_html_dir}/index.html
		echo "<A href=./${render_uuid}/index.html>${bellaNodeType} &nbsp; > &nbsp; ${bella_scene} &nbsp; > &nbsp; ${bellaNode} &nbsp; > &nbsp; ${bellaNodeAttribute}</a><br>" >> ${render_besp_dir}/directory.html

		unset insert0
		for ((i = 1 ; i <= ${bellaSliderFrames} ; i++ )); do 

			if ! [ $BESP_MODE == "generate_besp" ] && ! [ $bellaOrbitDegrees == "0"]; then
				#orbit
				func_lerp 0 $bellaOrbitDegrees $i ${bellaSliderFrames}
				func_dot_product_mat4 ${func_lerp_result} ${i} ${bellaSliderFrames}
				insert2="$selectCameraXform.steps[0].xform=mat4( ${resultingMat4[@]} );"
			fi
			padded=$(printf "%04d" $((i)))
			if [ $bellaSliderType == "rgba" ]; then
				bella_rgba_to_arr "${bellaSliderStart}"
				computedSliderStart=(${func_bella_rgba_to_arr_return[@]})
				bella_rgba_to_arr "${bellaSliderEnd}"
				computedSliderEnd=(${func_bella_rgba_to_arr_return[@]})
				func_lerp ${computedSliderStart[0]} ${computedSliderEnd[0]} ${i} ${bellaSliderFrames} 
    			red=$(printf "%.*f" 3 $func_lerp_result)
				func_lerp ${computedSliderStart[1]} ${computedSliderEnd[1]} ${i} ${bellaSliderFrames} 
    			green=$(printf "%.*f" 3 $func_lerp_result)
				func_lerp ${computedSliderStart[2]} ${computedSliderEnd[2]} ${i} ${bellaSliderFrames} 
    			blue=$(printf "%.*f" 3 $func_lerp_result)
				func_lerp ${computedSliderStart[3]} ${computedSliderEnd[3]} ${i} ${bellaSliderFrames} 
    			alpha=$(printf "%.*f" 3 $func_lerp_result)
    			animated="rgba( $red $green $blue $alpha )"
				echo "bellaSteps[$((i))]=\"${animated}\"" >> ${render_html_dir}/bella.js
			else
				animated=$(awk "BEGIN {print (($bellaSliderEnd-($bellaSliderStart))*(($i-1)/($bellaSliderFrames-1)))+($bellaSliderStart)}")
				if [ ${animated:0:1} == "." ]; then
					animated="0${animated}f"
				elif [ ${animated:0:2} == "-." ]; then
					animated="-0${animated:1}f"
				fi
				echo "bellaSteps[$((i))]=\"$(printf %.3f ${animated}) ${bellaUnits}\";" >> ${render_html_dir}/bella.js
			fi
			#echo "bellaSteps[$((i))]=\"$(printf %.3f ${animated}) ${bellaUnits}\" ;" >> ${render_html_dir}/bella.js

			if [ $i == 1 ]; then
				for ((c = 0 ; c < ${#bespNode[@]} ; c++ )); do
					insert0="${insert0}${bespNode[$c]} ${bespNodeName[$c]}; "
					echo $insert0
				done

				# Substitute .besp variables with scene node uuids selected by user
				for ((c = 0 ; c < ${#bellaFragment[@]} ; c++ )); do
					theFragment=${bellaFragment[$c]}
                	backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${bellaFragment[$c]})"
                    if [[ "${theFragment%selectXform*}" == "\$" ]] ; then
						substituteUserVar=${bellaFragment[$c]/\$selectXform/$selectXform}
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${substituteUserVar})"
						insert1="${insert1}${substituteUserVar} "
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
                    elif [[ "${theFragment%selectMesh*}" == "\$" ]] ; then
						substituteUserVar=${bellaFragment[$c]/\$selectMesh/$selectMesh}
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${substituteUserVar})"
						insert1="${insert1}${substituteUserVar} "
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
                    elif [[ "${theFragment%selectMaterial*}" == "\$" ]] ; then
						substituteUserVar=${bellaFragment[$c]/\$selectMaterial/$selectMaterial}
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${substituteUserVar})"
						insert1="${insert1}${substituteUserVar} "
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
					else
						insert1="${insert1}${bellaFragment[$c]} "
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${bellaFragment[$c]})"
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
					fi
				done
			fi

			if ! [ $BESP_MODE == "generate_besp" ]; then
                backQuoteInsert="$(sed -e 's/\"/\\\"/g' <<<${insert1})"
				echo ${bella_cli_path} -i:\""${bella_scene}"\" -on:\""bella${padded}"\" -pf:\""${BELLA_PARSE_FRAGMENT}"\" -pf:\""${insert0}"\" -pf:\""${insert2}"\" -pf:\""${backQuoteInsert}"\" -pf:\""${bellaSliderNode}.${bellaNodeAttribute}=${animated};"\" -pf:\""nnsettings.threads=0;nnbeautyPass.outputExt=\\\".jpg\\\";"\"  -od:\""${render_html_dir}/"\" 
				${bella_cli_path} -i:"${bella_scene}" -on:"bella${padded}" -pf:"${BELLA_PARSE_FRAGMENT}" -pf:"${insert0}" -pf:"${insert1}" -pf:"${insert2}" -pf:"${bellaSliderNode}.${bellaNodeAttribute}=${animated};" -pf:"nnsettings.threads=0;nnbeautyPass.outputExt=\".jpg\";"  -od:"${render_html_dir}/" 
			fi
		done	
	done
fi

cat templates_html/postdirectory.html >> ${render_besp_dir}/directory.html
if [ $BESP_MODE == "generate_besp" ]; then
	echo "Finished generating .besp files, during alpha testing you need to re-run this script to render the jpegs"
else
	if [[ "$OSTYPE" == "darwin"* ]]; then
		open ./${BELLA_VERSION}/${bellaGroup}/directory.html
	elif [[ "$OSTYPE" == "msys"* ]]; then
		microsoftedge.exe "${PWD}/${BELLA_VERSION}/${bellaGroup}/directory.html"
	fi
fi


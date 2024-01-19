#!/bin/bash

# If .besp and .bsa files already exist, there is the option to NOT overwrite them and to 
# generate a new index 

if [ -z ${BELLA_VERSION} ]; then
	BELLA_VERSION="23.6.0"
fi

BESP_MODE="generate_besp"
bellaGroup="environment"
bellaMaterials=( "blend" "carPaint" "conductor" "dielectric" "emitterProjector" "emitter" "orenNayer" "quickMaterial" )
bellaSpecial=( "box" "sphere" "volumetricMaterial" "polygon")

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
		template_basename="$(basename "$each_template")"
		template_besp_dir="$(dirname "$each_template")"
		template_uuid=${template_basename%.*} 
		#echo "GEN BASE $template_basename DIR $template_besp_dir UUID $template_uuid SCENE $scene"

        ####
        stepIndex=0
        unset bellaFragment
        unset bespNode
		stepFragmentIndex=0
		stepSelectIndex=0
		bespNodeIndex=0
        while read each_line; do
            if ! [[ -z ${each_line} ]] && ! [[ ${each_line:0:1} == "#" ]]; then
				echo ${each_line}
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
                    elif [ ${less_trailing_whitespace%Node*=*} == "besp" ] ; then
                        bespNode[${bespNodeIndex}]=${less_trailing_whitespace#*bespNode*=} 
                        bespNodeIndex=$((bespNodeIndex+1))
                    elif [ ${less_trailing_whitespace%=*} == "selectXform" ] ; then
                        selectXform=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectMesh" ] ; then
                        selectMesh=${less_trailing_whitespace#*=} 

                    fi
                fi
            fi
            #done
        done <${each_template}

		if [ -z $selectXform ]; then
			echo "Select xform to assign to variable \$selectXform"
			select_nodes=$("${bella_cli_path}" -ln:"xform" -i:${scene})
			node_names_with_spaces="${select_nodes//,/ }"
			select selectXform in $node_names_with_spaces
			do
				break
			done
			echo "Select mesh to assign to variable \$selectMesh"
			select_nodes=$("${bella_cli_path}" -ln:"mesh" -i:${scene})
			node_names_with_spaces="${select_nodes//,/ }"
			select selectMesh in $node_names_with_spaces
			do
				break
			done
		fi

        echo "bellaSliderStart=${bellaSliderStart}" > ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaSliderEnd=${bellaSliderEnd}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        echo "bellaSliderFrames=${bellaSliderFrames}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
		for ((i = 0 ; i < ${#bespNode[@]} ; i++ )); do
        	echo "bespNode=${bespNode[$i]}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
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

        #rm -f  ${render_besp_dir}/${scene}.${template_uuid}.bsa
        for ((i = 0 ; i < ${#bellaFragment[@]} ; i++ )); do
        	echo "bellaFragment=${bellaFragment[$i]}" >> ${render_besp_dir}/${scene}.${template_uuid}.besp
        done
	done
fi


# COMMON PASS
if [ ${idle} == "1" ]; then
	# Get list of all besp files to be processed
	besp_files=$BELLA_VERSION/${bellaGroup}/*.besp
	# Init directory.html
	cat templates_html/predirectory.html > ./${BELLA_VERSION}/${bellaGroup}/directory.html

	for each_besp in $besp_files; do
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
        unset bellaFragment
		unset insert0
		unset insert1
        echo "============="
        while read each_line; do
            echo $each_line
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
                        #bellaSliderFrames="3"
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
                    elif [ ${less_trailing_whitespace%Node*=*} == "besp" ] ; then
                        bespNode[${bespNodeIndex}]=${less_trailing_whitespace#*bespNode*=} 
                        bespNodeIndex=$((bespNodeIndex+1))
                    elif [ ${less_trailing_whitespace%=*} == "selectMesh" ] ; then
                        selectMesh=${less_trailing_whitespace#*=} 
                    elif [ ${less_trailing_whitespace%=*} == "selectXform" ] ; then
                        selectXform=${less_trailing_whitespace#*=} 
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
			padded=$(printf "%04d" $((i)))
			animated=$(awk "BEGIN {print (($bellaSliderEnd-($bellaSliderStart))*(($i-1)/($bellaSliderFrames-1)))+($bellaSliderStart)}")
			if [ ${animated:0:1} == "." ]; then
				animated="0${animated}"
			elif [ ${animated:0:2} == "-." ]; then
				animated="-0${animated:1}"
			fi
			echo "bellaSteps[$((i))]=\"$(printf %.3f ${animated}) ${bellaUnits}\" ;" >> ${render_html_dir}/bella.js

			if [ $i == 1 ]; then
				for ((c = 0 ; c < ${#bespNode[@]} ; c++ )); do
					if [[ ${bellaMaterials[*]} =~ ${bespNode[$c]} ]]; then
						insert0="${insert0}${bespNode[$c]} bespNode${c}; "
					elif [ ${bespNode[$c]} == "scattering" ]; then
						insert0="${insert0}${bespNode[$c]} bespNode${c};${selectXform}.scattering=bespNode${c}; "
					elif [ ${bespNode[$c]} == "thinLens" ]; then
						insert0="${insert0}nncamera.pinhole=false; "
					elif [[ ${bellaSpecial[*]} =~ ${bespNode[$c]} ]]; then
						insert0="${insert0}${bespNode[$c]} bespNode${c}; "
					elif [ ${bespNode[$c]} == "grass" ]; then
						insert0="${insert0}${bespNode[$c]} bespNode${c};${selectMesh}.grass=bespNode${c}; "
					fi
				done

				# Substitute .besp variables with scene node uuids selected by user
				for ((c = 0 ; c < ${#bellaFragment[@]} ; c++ )); do
					theFragment=${bellaFragment[$c]}
                	backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${bellaFragment[$c]})"
					#echo $backQuoteFragment
                    if [[ "${theFragment%selectXform*}" == "\$" ]] ; then
						substituteUserVar=${bellaFragment[$c]/\$selectXform/$selectXform}
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${substituteUserVar})"
						#insert1="${insert1}${bellaFragment[$c]/\$selectXform/$selectXform} "
						insert1="${insert1}${substituteUserVar} "
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
                    elif [[ "${theFragment%selectMesh*}" == "\$" ]] ; then
						substituteUserVar=${bellaFragment[$c]/\$selectMesh/$selectMesh}
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${substituteUserVar})"
						insert1="${insert1}${substituteUserVar} "
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
					else
						insert1="${insert1}${bellaFragment[$c]} "
						backQuoteFragment="$(sed -e 's/\"/\\\"/g' <<<${bellaFragment[$c]})"
						echo "bellaQueue[$((c))]=\"${backQuoteFragment}\";" >> ${render_html_dir}/bella.js
					fi
				done
				#echo "parseFragment0=\"${insert0}\";" >> ${render_html_dir}/bella.js
				#echo "parseFragment1=\"${insert1}\";" >> ${render_html_dir}/bella.js
				echo "parseFragment0=\"0\";" >> ${render_html_dir}/bella.js
				echo "parseFragment1=\"0\";" >> ${render_html_dir}/bella.js

			fi

			if ! [ $BESP_MODE == "generate_besp" ]; then
                backQuoteInsert="$(sed -e 's/\"/\\\"/g' <<<${insert1})"
				echo ${bella_cli_path} -i:\""${bella_scene}"\" -on:\""bella${padded}"\" -pf:\""${BELLA_PARSE_FRAGMENT}"\" -pf:\""${insert0}"\" -pf:\""${backQuoteInsert}"\" -pf:\""${bellaSliderNode}.${bellaNodeAttribute}=${animated}f;"\" -pf:\""nnsettings.threads=0;nnbeautyPass.outputExt=\\\".jpg\\\";"\"  -od:\""${render_html_dir}/"\" 
				${bella_cli_path} -i:"${bella_scene}" -on:"bella${padded}" -pf:"${BELLA_PARSE_FRAGMENT}" -pf:"${insert0}" -pf:"${insert1}" -pf:"${bellaSliderNode}.${bellaNodeAttribute}=${animated}f;" -pf:"nnsettings.threads=0;nnbeautyPass.outputExt=\".jpg\";"  -od:"${render_html_dir}/" 
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
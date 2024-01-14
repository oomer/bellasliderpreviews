#!/bin/bash

# If .besp and .bsa files already exist, there is the option to NOT overwrite them and to 
# generate a new index 

if [ -z ${BELLA_VERSION} ]; then
	BELLA_VERSION="23.6.0"
fi

BESP_MODE="generate_besp"

if test -d ${BELLA_VERSION}; then
	echo -e "\nFound existing .besp and .bsa files"
	scene_files=${BELLA_VERSION}/material/*.besp
	select anim in overwrite_existing_besp render_existing_besp quit
	do
		break
	done
	if [ $REPLY == "1" ]; then
		rm -f ${BELLA_VERSION}/material/*.besp
		rm -f ${BELLA_VERSION}/material/*.bsa
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
	echo "hello"
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

#scene="butter.bsz"
#scene="orange-juice.bsz"
#xform_nodes=$(${bella_cli_path} -ln:"xform" -i:${scene})
#echo -e "\n$xform_nodes"
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
	xform_nodes=$("${bella_cli_path}" -ln:"xform" -i:${scene})

	echo -e "\nbellasliderpreview.sh will render using bella_cli to generate scrubbeable previews"
	echo "This supplements the bella docs with visual feedback on how each attribute affects the render"
	node_names_with_spaces="${xform_nodes//,/ }"

	echo -e "\nSelect a premade set of slider preview animations to render"
	echo "Your scene will locally render 30 frames for each attribute, meaning this will take a long time"
	select node_group in all environment camera light geometry material quit
	do
		break
	done

	if [ $node_group = "material" ] || [ $node_group = "all" ]; then

		echo -e "\nSelect the bella xform node that will be programmatically assigned new materials"
		echo -e "Children nodes that inherit from this node will get the new material applied"

		select node_name in $node_names_with_spaces quit
		do
			break
		done

		if ! [ ${node_name} == "quit" ]; then
			echo "$REPLY $node_name"
		else
			exit
		fi
	fi
fi

idle="1"

node_group="material"
# Common toplevel dir for intermediate files, a subdir called render_html_dir will store html and jpg
render_besp_dir="${BELLA_VERSION}/${node_group}"
mkdir -p ${render_besp_dir}

# GENERATE PASS, converts templates to useable besp
if [ $BESP_MODE == "generate_besp" ]; then
	# Get list of all template .besp files
	template_files=templates_besp/${node_group}/*.besp
	for each_template in $template_files; do
		template_basename="$(basename "$each_template")"
		template_besp_dir="$(dirname "$each_template")"
		template_uuid=${template_basename%.*} 
		echo "GEN BASE $template_basename DIR $template_besp_dir UUID $template_uuid SCENE $scene"
		# copy template .besp to current stack
		cp $each_template "${render_besp_dir}/${scene}.${template_uuid}.besp"
		# [ ] Maybe a .bsa file MUST exist so we can rid this check
		if test -f  "${template_besp_dir}/${template_uuid}.bsa"; then 
			sed s/BeSPREPLACEME/${node_name}/g "${template_besp_dir}/${template_uuid}.bsa" > "${render_besp_dir}/${scene}.${template_uuid}.bsa"
		fi
	done
fi

# COMMON PASS
if [ ${idle} == "1" ]; then
	# Get list of all besp files to be processed
	besp_files=$BELLA_VERSION/${node_group}/*.besp
	# Init directory.html
	cat templates_html/predirectory.html > ./${BELLA_VERSION}/${node_group}/directory.html

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
		echo "EXIST BASE $render_basename DIR $render_besp_dir UUID $render_uuid SCENE $bella_scene"

		# bella.js
    	bellaType=$(sed '4!d' ${each_besp})
    	bellaNode=$(sed '5!d' ${each_besp}) 
    	bellaAttribute=$(sed '6!d' ${each_besp})
    	echo "bellaType=\"${bellaType}\";" > ${render_html_dir}/bella.js
    	echo "bellaNode=\"${bellaNode}\";" >> ${render_html_dir}/bella.js
    	echo "bellaAttribute=\"${bellaAttribute}\";" >> ${render_html_dir}/bella.js
		echo "bellaSteps=[];" >> ${render_html_dir}/bella.js

		# html
		cp ./templates_html/template.html ${render_html_dir}/index.html
		echo "<A href=./${render_uuid}/index.html>${bella_scene} &nbsp; ${bellaType} &nbsp; > &nbsp; ${bella_scene} &nbsp; > &nbsp; ${bellaNode} &nbsp; > &nbsp; ${bellaAttribute}</a><br>" >> ${render_besp_dir}/directory.html

		echo "Animation Rendering started for: $each_besp"

		# calculate anim
		anim1startline=$(sed '1!d' ${each_besp})
		attr=${anim1startline%=*}
		anim1start0=${anim1startline#*=}
		anim1start=${anim1start0:0:${#anim1start0}-2}
		anim1endline=$(sed '2!d' ${each_besp})
		anim1end0=${anim1endline#*=}
		anim1end=${anim1end0:0:${#anim1end0}-2}
		frames=$(sed '3!d' ${each_besp})

		for ((i = 1 ; i <= ${frames} ; i++ )); do 
			if test -f ${save_dir}.bsa; then
				insert1=$(sed '1!d' ${save_dir}.bsa)
			else
				insert1=""
			fi
			padded=$(printf "%04d" $((i)))
			animated=$(awk "BEGIN {print (($anim1end-($anim1start))*(($i-1)/($frames-1)))+($anim1start)}")
			if [ ${animated:0:1} == "." ]; then
				animated="0${animated}"
			elif [ ${animated:0:2} == "-." ]; then
				animated="-0${animated:1}"
			fi
			echo "bellaSteps[$((i))]=\"$(printf %.3f ${animated})\";" >> ${render_html_dir}/bella.js
			if test -f  "${render_besp_dir}/${render_uuid}.bsa"; then 
				insert1=$(sed '1!d' ${render_besp_dir}/${render_uuid}.bsa)
			else
				insert1=""
			fi
			#echo ${bella_cli_path} -i:\""${bella_scene}"\" -on:\""bella${padded}"\" -pf:\""${BELLA_PARSE_FRAGMENT}"\" -pf:\""${insert1}"\" -pf:\""${attr}=${animated}f;"\" -pf:\""nnsettings.threads=0;"\"  -od:\""${render_html_dir}/"\" 
			${bella_cli_path} -i:"${bella_scene}" -on:"bella${padded}" -pf:"${BELLA_PARSE_FRAGMENT}" -pf:"${insert1}" -pf:"${attr}=${animated}f;" -pf:"nnsettings.threads=0;"  -od:"${render_html_dir}/" 
		done	
		echo "hhh"
	done
fi

cat templates_html/postdirectory.html >> ${render_besp_dir}/directory.html

if [[ "$OSTYPE" == "darwin"* ]]; then
	open ./${BELLA_VERSION}/material/directory.html
elif [[ "$OSTYPE" == "msys"* ]]; then
	microsoftedge.exe "${PWD}/${BELLA_VERSION}/material/directory.html"
fi

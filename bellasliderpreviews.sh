#!/bin/bash
if [ -z ${BELLA_VERSION} ]; then
	BELLA_VERSION="23.6.0"
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
			#sudo dnf -y install bc
		#  Debian based
		else
			sudo apt -y update
			sudo apt -y install mesa-vulkan-drivers
			sudo apt -y install libgl1-mesa-glx
			#sudo apt -y install bc
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
scene_files=./*.bs*
select scene in ${scene_files} quit
do
	break
done
if ! [ ${scene} == "quit" ]; then
	echo "$REPLY $scene"
else
	exit
fi
echo $scene

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

#bsz_files=*.bsz
#anim_files=${BELLA_VERSION}/material/*.anim
template_files=./templates/${node_group}/*.anim

if ! test -f "bella.log" ; then
	idle="1"
else
	is_idle="$(pgrep bella_cli)"

	if [ -z ${is_idle} ]; then
		idle="1"
	else
		idle="0"
	fi
fi
save_node_dir="./${BELLA_VERSION}/${node_group}"
cat templates_html/predirectory.html > ${save_node_dir}/directory.html

if [ ${idle} == "1" ]; then
	for each in $template_files
	do
		prefix_bsz=${scene%.*} 
		basename="$(basename "$each")"
		parent_dir="$(dirname "$each")"
		parent_anim_dir="$(dirname "$each")"
		#parentdir="material"
		prefix_anim=${basename%.*} 
		#echo "$basename $parentdir $prefix"
		save_html_dir="./${BELLA_VERSION}/${node_group}/${scene}.${prefix_anim}"
		save_anim_dir="./${BELLA_VERSION}/${node_group}"
		#echo $save_html_dir
		mkdir -p ${save_html_dir}
    	bellaType=$(sed '4!d' ${each})
    	bellaNode=$(sed '5!d' ${each}) 
    	bellaAttribute=$(sed '6!d' ${each})
    	echo "bellaType=\"${bellaType}\";" > ${save_html_dir}/bella.js
    	echo "bellaNode=\"${bellaNode}\";" >> ${save_html_dir}/bella.js
    	echo "bellaAttribute=\"${bellaAttribute}\";" >> ${save_html_dir}/bella.js
		echo "bellaSteps=[];" >> ${save_html_dir}/bella.js
		cp ./templates_html/template.html ${save_html_dir}/index.html
		echo "<A href=./${scene}.${prefix_anim}/index.html>${bellaType} &nbsp; > &nbsp; ${scene} &nbsp; > &nbsp; ${bellaNode} &nbsp; > &nbsp; ${bellaAttribute}</a><br>" >> ${save_node_dir}/directory.html
		#echo "Animation Rendering started for: $each"

		anim1startline=$(sed '1!d' ${each})
		attr=${anim1startline%=*}
		anim1start0=${anim1startline#*=}
		anim1start=${anim1start0:0:${#anim1start0}-2}
		anim1endline=$(sed '2!d' ${each})
		anim1end0=${anim1endline#*=}
		anim1end=${anim1end0:0:${#anim1end0}-2}
		frames=$(sed '3!d' ${each})

		for ((i = 1 ; i <= ${frames} ; i++ )); do 
			if test -f ${save_dir}.bsa; then
				insert1=$(sed '1!d' ${save_dir}.bsa)
			else
				insert1=""
			fi

			padded=$(printf "%04d" $((i)))
			#animated=$(echo "scale=5; ((${anim1end}-(${anim1start}))*($((i-1))/$((frames-1))))+${anim1start}" | bc)
			animated=$(awk "BEGIN {print (($anim1end-$anim1start)*(($i-1)/($frames-1)))+$anim1start}")
			echo "${animated} ${animated2}"
			if [ ${animated:0:1} == "." ]; then
				animated="0${animated}"
			elif [ ${animated:0:2} == "-." ]; then
				animated="-0${animated:1}"
			fi
			echo "bellaSteps[$((i))]=\"$(printf %.3f ${animated})\";" >> ${save_html_dir}/bella.js
			cp $each "${save_anim_dir}/${scene}.${prefix_anim}.anim"
			if test -f  "${parent_dir}/${prefix_anim}.bsa"; then 
				sed s/BeSPREPLACEME/${node_name}/g "${parent_dir}/${prefix_anim}.bsa" > "${save_anim_dir}/${scene}.${prefix_anim}.bsa"
				insert1=$(sed '1!d' ${save_anim_dir}/${scene}.${prefix_anim}.bsa)
			else
				insert1=""
				#cp "${parent_dir}/${prefix_anim}.bsa" "${save_anim_dir}/${scene}.${prefix_anim}.bsa"
			fi
			echo ./bella_cli -i:"${scene}" -on:"bella${padded}" -pf:"${BELLA_PARSE_FRAGMENT}" -pf:"${insert1}" -pf:"${attr}=${animated}f;" -pf:"nnsettings.threads=0;"  -od:"${save_html_dir}/" 
			"${bella_cli_path}" -i:"${scene}" -on:"bella${padded}" -pf:"${BELLA_PARSE_FRAGMENT}" -pf:"${insert1}" -pf:"${attr}=${animated}f;" -pf:"nnsettings.threads=0;"  -od:"${save_html_dir}/" 
		done	
	done
fi

cat templates_html/postdirectory.html >> ${save_node_dir}/directory.html

if [[ "$OSTYPE" == "darwin"* ]]; then
	open ./${BELLA_VERSION}/material/directory.html
elif [[ "$OSTYPE" == "msys"* ]]; then
	microsoftedge.exe "${PWD}/${BELLA_VERSION}/material/directory.html"
fi

#!/bin/bash

CMD=$1
PROJECT=$2
DEPENDS_OFF=$3
CURRENT_PATH=$(pwd)

function red() {
	echo -e "\033[0;31m$*\033[0m"
}

function green() {
	echo -e "\033[0;32m$*\033[0m"
}

function parse_yaml {
	local prefix=$2
	local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @ | tr @ '\034')
	sed -ne "s|,$s\]$s\$|]|" \
		-e "s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s\]|\1\2:\n\1  - \3|;p" "$1" |
		sed -ne "s|^\($s\):|\1|" \
			-e "s|^\($s\)-$s\(.*\)$s\$|\1$fs$fs\2|p" \
			-e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" |
		awk -F"$fs" '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]; idx[i]=0}}
      if(length($2)== 0){  vname[indent]= ++idx[indent] };
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) { vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\%s\n", "'"$prefix"'",vn, vname[indent], $3);
      }
   }'
}

CONFIG=()
UPDATE_COMMANDS=()
PROJECTS_DEPENDENCY_MAP=()

OIFS="$IFS"
IFS=$'\n'
for ctx in $(parse_yaml config.yaml); do
	IFS='='
	exp=($ctx)
	IFS=$'\n'
	key="${exp[0]}"
	value="${exp[1]}"
	if [[ $key =~ "dependency_map" ]]; then
		value=${value//\"/}
		PROJECTS_DEPENDENCY_MAP+=($value)
	elif [[ $key =~ "update_project_cmd" ]]; then
		value=${value//\"/}
		UPDATE_COMMANDS+=($value)
	else
		CONFIG+=("$key::$value")
	fi
done

function get_config() {
	find_key=$1
	for config in "${CONFIG[@]}"; do
		IFS='::'
		exp=($config)
		unset IFS
		key="${exp[0]}"
		value="${exp[2]}"
		if [[ $find_key == "$key" ]]; then
			echo "$value"
		fi
	done
}

IFS="$OIFS"
LOG_FOLDER=$(get_config log_folder)
PROJECTS_PATH=$(get_config project_path)

mkdir -p "$LOG_FOLDER"

function _help() {
	echo -e "Usages;\n"
	echo -e "project-manager.sh start                             // start projects"
	echo -e "project-manager.sh start <project_name>              // start project with dependencies"
	echo -e "project-manager.sh start <project_name> depends_off  // start project\n"

	echo -e "project-manager.sh stop                       // stops projects."
	echo -e "project-manager.sh stop <project_name>        // stops project\n"

	echo -e "project-manager.sh restart                    // restart projects"
	echo -e "project-manager.sh restart <project_name>     // restart project\n"

	echo -e "project-manager.sh update                     // update projects"
	echo -e "project-manager.sh update <project_name>      // update project\n"

	echo -e "project-manager.sh show                       // lists running projects\n"

	echo -e "project-manager.sh watch                      // show projects logs"
	echo -e "project-manager.sh watch <project_namee>      // show project logs\n"

	echo -e "project-manager.sh remove-logs                // remove projects logs file"
	echo -e "project-manager.sh remove-logs <project_name> // remove project logs file"
}

function update-project() {
	project="$1"
	red "[**] ${project}"
	check_diff=$(git diff)
	if [ "$check_diff" ]; then
		red "There are uncommitted changes in the ${project} project"
		while true; do
			read -r -p "Should I continue anyway? yes/no -> " yn
			case $yn in
			[Yy]*)
				uncommitted_cmd=$(get_config uncommitted_cmd | tr -d '"')
				uncommitted_cmd_msg=$(get_config uncommitted_cmd_msg | tr -d '"')
				eval "$uncommitted_cmd"
				green "$uncommitted_cmd_msg"

				break
				;;
			[Nn]*) return ;;
			*) echo "Please answer yes or no." ;;
			esac
		done
	fi

	for cmd in "${UPDATE_COMMANDS[@]}"; do
		eval "$cmd"
	done
}

function update-projects() {
	for project_path in "${PROJECTS_PATH}"/*; do
		cd "$project_path" || return
		project_name=$(basename "$project_path")
		update-project "$project_name"
		cd "$CURRENT_PATH" || return
	done
}

function stop-project() {
	project=$1
	is_running=$(screen -ls | grep "$project")
	if [ "$project" == "" ]; then
		red "enter the project you want to stop"
		return
	elif [ "$is_running" == "" ]; then
		red "${project} is not running"
		return
	fi

	green "[*] ${project} is stopping."
	screen -S "$project" -X quit >/dev/null
	screen -wipe >/dev/null
	pgrep -f "${PROJECTS_PATH}/${project}" | xargs kill
}

function stop-projects() {
	for dependency_map in "${PROJECTS_DEPENDENCY_MAP[@]}"; do
		project=$(echo "$dependency_map" | cut -d ":" -f 1)
		stop-project "$project"
	done
}

function watch-projects-logs() {
	project=$1
	if [[ "$project" ]]; then
		tail -f "$LOG_FOLDER/$project.log"
	else
		tail -f "$LOG_FOLDER/"*
	fi
}

function remove-projects-logs() {
	project=$1
	if [[ "$project" ]]; then
		rm -rf "$LOG_FOLDER/$project.log"
	else
		rm -rf "$LOG_FOLDER/"*
	fi
}

function start-project() {
	project_path=$1
	project=$2
	is_already_running=$(screen -ls | grep "$project")
	if [[ "$is_already_running" && "$DEPENDS_OFF" == "" ]]; then
		return
	elif [ "$is_already_running" ]; then
		red "${project} already running!"
		while true; do
			read -r -p "Do you want it restarted? yes/no -> " yn
			case $yn in
			[Yy]*)
				stop-project "$project"
				break
				;;
			[Nn]*) return ;;
			*) echo "Please answer yes or no." ;;
			esac
		done
	fi
	prefix_cmd=$(get_config start_project_cmd)
	suffix_cmd=$(get_config start_project_suffix_cmd)
	cmd="${prefix_cmd} ${suffix_cmd}"
	cmd=${cmd//\"/}
	cmd=$(echo "${cmd/\$project_path/$project_path}")
	cmd=$(echo "${cmd/\$project/$project}")
	cmd=$(echo "${cmd/\$LOG_FOLDER/$LOG_FOLDER}")
	sleep 1
	screen -SU "$project" -d -m bash -c "${cmd}"
	green "[*] ${project} is running."
}

function get-dependency-map() {
	project=$1
	for dependency_map in "${PROJECTS_DEPENDENCY_MAP[@]}"; do
		depend_projects=$(echo "$dependency_map" | cut -d ':' -f 1)
		main_project=${depend_projects[0]}
		if [[ "$main_project" == "$project" ]]; then
			echo "$dependency_map"
		fi
	done
}

function prepare-start-project() {
	project=$1
	start_dependency=$2
	main_project=$project
	if [ "$start_dependency" != "depends_off" ]; then
		dependency_map=$(get-dependency-map "$project")
		dependency_projects=$(echo "$dependency_map" | tr ":" "\n")
		counter=0
		for project_name in $dependency_projects:; do
			counter=$(($counter + 1))
			if [[ $counter -eq 1 ]]; then
				continue
			fi
			project_name=$(echo "${project_name//:/}")
			start-project "${PROJECTS_PATH}/$project_name" "$project_name"
		done
	fi
	start-project "${PROJECTS_PATH}/$main_project" "$main_project"
}

function start-projects() {
	for dependency_map in "${PROJECTS_DEPENDENCY_MAP[@]}"; do
		project=$(echo "$dependency_map" | cut -d ":" -f 1)
		prepare-start-project "$project"
	done
}

function show-projects() {
	for dependency_map in "${PROJECTS_DEPENDENCY_MAP[@]}"; do
		project=$(echo "$dependency_map" | cut -d ":" -f 1)
		check=$(screen -ls | grep "$project")
		if [[ "$check" ]]; then
			green "$project running."
		fi
	done
}

case $CMD in
"start")
	if [ "$PROJECT" ]; then
		prepare-start-project "$PROJECT" "$DEPENDS_OFF"
	else
		start-projects
	fi
	;;

"stop")
	if [ "$PROJECT" ]; then
		stop-project "$PROJECT"
	else
		stop-projects
	fi
	;;

"restart")
	if [ "$PROJECT" ]; then
		stop-project "$PROJECT"
		prepare-start-project "$PROJECT"
	else
		stop-projects
		start-projects
	fi
	;;

"update")
	if [ "$PROJECT" ]; then
		project_path="${PROJECTS_PATH}/${PROJECT}"
		cd "$project_path" || return
		update-project "$PROJECT"
		cd "$CURRENT_PATH" || exit
	else
		update-projects
	fi
	;;

"watch")
	if [ "$PROJECT" ]; then
		watch-projects-logs "$PROJECT"
	else
		watch-projects-logs
	fi
	;;

"show")
	show-projects
	;;

"help")
	_help
	;;

"remove-logs")
	if [ "$PROJECT" ]; then
		remove-projects-logs "$PROJECT"
	else
		remove-projects-logs
	fi
	;;

*)
	_help
	;;
esac

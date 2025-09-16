#!/usr/bin/env bash

set -e
# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"

function ScriptExit {
	local exitcode="${?}" idx line file func
	# Show the stack in case of an error.
	if [[ "${exitcode}" -ne 0 ]]; then
		# Create
		echo -e "\n--- Call Stack ---"
		# Perform a stack trace.
		idx=0
		while read -r line func file < <(caller $idx); do
			# When the line number is 1 clear the line number and use the passed failed command.
			[[ "${line}" -eq 1 ]] && line=""
			echo "[$idx] $file:$line $func(): $([[ -n "${line}" ]] && sed -n "${line}"p "$file" || echo "$3")"
			((idx += 1))
		done
		echo "! Exitcode: ${exitcode}"
	fi
	# Report execution time.
	#echo "- $(basename "${0}"), executed in ${SECONDS}s."
	# Propagate the exit code.
	exit "${exitcode}"
}

## Trap script exit with function.
trap 'ScriptExit "${BASH_SOURCE}" "${BASH_LINENO}" "${BASH_COMMAND}"' EXIT

# Prints the help.
#
function show_help {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] <command>
  Configures and runs a LLM using Docker Model Runner (DMR).

  Options:
    -h, --help : Show this help.

  Commands:
    deps        : Install dependencies.
    update      : Updates the model runner.
    pull        : Pulls the configured AI models but also starts the model runner container.
    run         : Runs the Docker model interactively on the command line.
    list        : List the AI models currently available to the model runner.
    test        : Tests the API using curl and the first AI model.
    start       : Starts running the docker model runner container in the background.
    stop        : Stops the docker model runner in the background.
    status      : Reports the status on the container.
    restart-no  : Set the container to start at host-system boot. (This is the default)
    restart-yes : Set the container to not start at host-system boot.

  Model list:"
	for ai_model in "${ai_models[@]}"; do
		echo "    * ${ai_model}"
	done

}

# Container name running the models. (Fixed by Docker plugin?)
dmr_container="docker-model-runner"
# The AI models used.
ai_models=("ai/smollm2:360M-Q4_K_M")
ai_models+=("ai/qwen3-coder:30B-A3B-UD-Q4_K_XL")
# Required packages.
declare -A packages
packages["Docker Model Plugin"]="docker-model-plugin"

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	show_help
	exit 0
fi

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Parse options.
temp=$(getopt -o 'h' --long 'help' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	show_help
	exit 1
fi

eval set -- "${temp}"
unset temp
while true; do
	case "$1" in

		-h | --help)
			show_help
			exit 0
			;;

		'--')
			shift
			break
			;;

		*)
			echo "Internal error on argument (${1}) !" >&2
			exit 1
			;;
	esac
done

# Get the subcommand.
cmd=""
if [[ $# -gt 0 ]]; then
	cmd="$1"
	shift
fi

# Process subcommand.
case "${cmd}" in
	deps)
		# Check if 'docker-ce' package is installed from the correct source
		if apt-cache policy docker-ce | grep -A 1 "^ \*\*\*.*" | tail -n 1 | grep -q '://download.docker.com/linux/'; then
			# Install all required and dependent packages.
			for name in "${!packages[@]}"; do
				if dpkg-query -W -f='${Status}' "${packages["${name}"]}" 2>/dev/null | grep -q "ok installed"; then
					echo "Package '$name' (${packages["${name}"]}) is installed."
				else
					echo "Elevating to install package: ${packages["${name}"]}"
					if sudo apt-get install "${packages["${name}"]}"; then
						exit 1
					fi
				fi
			done
			docker model version
		else
			echo "Docker-CE is not installed from 'download.docker.com/linux'."
		fi
		;;

	update)
		docker model uninstall-runner --images && docker model install-runner
		;;

	pull)
		echo "Pulling the models:" "${ai_models[@]}"
		for ai_model in "${ai_models[@]}"; do
			docker model pull "${ai_model}"
		done
		;;

	run)
		docker model run "${ai_models[0]}"
		;;

	start)
		docker model status
		;;

	list)
		docker model list
		;;

	status)
		#docker inspect -f '{{.Name}} - {{.HostConfig.RestartPolicy.Name}}'
		docker inspect -f 'Name: {{.Name}}
Image: {{.Config.Image}}
Status: {{.State.Status}}
Restart: {{.HostConfig.RestartPolicy.Name}}
Uptime: {{.State.StartedAt}}
MemoryLimit: {{.HostConfig.Memory}}
CPUs: {{.HostConfig.NanoCpus}}
IP: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${dmr_container}"
		;;

	restart-no)
		docker update --restart=no "${dmr_container}"
		;;

	restart-yes)
		docker update --restart=always "${dmr_container}"
		;;

	stop)
		# Stop this docker container only.
		cntr_id="$(docker ps --filter name="${dmr_container}" --quiet)"
		if [[ -n "${cntr_id}" ]]; then
			echo "Container ID is '${cntr_id}' and performing '${cmd}' command."
			docker "${cmd}" "${cntr_id}"
		else
			echo "Container '${dmr_container}' is not running."
		fi
		;;

	test)
		query_string="$(curl -ss --fail-with-body "http://localhost:12434/engines/llama.cpp/v1/chat/completions" \
			-H "Content-Type: application/json" -d \
			"{
	\"model\": \"${ai_models[0]}\",
	\"messages\": [
		{\"role\":\"system\",\"content\":\"You are a helpful coding assistant.\"},
		{\"role\":\"user\",\"content\":\"Create a simple CLI hello world app in Python?\"}
	],
	\"temperature\": 0.7,
	\"top_p\": 0.8,
	\"top_k\": 20,
	\"repetition_penalty\":1.05,
	\"max_tokens\":512
}")"
		echo -e "$(echo "${query_string}" | jq .choices[0].message.content)"
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		show_help
		exit 1
		;;
esac

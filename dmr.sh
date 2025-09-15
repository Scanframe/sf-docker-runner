#!/usr/bin/env bash

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"

# Prints the help.
#
function show_help {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] <command>
  Configures and runs a LLM using Docker Model Runner (DMR).

  Options:
    -h, --help    : Show this help.

  Commands:
    deps   : Install dependencies.
    update : Updates the model runner.
    pull   : Pulls the AI model but also starts the model runner container.
    run    : Runs the Docker model interactively on the command line.
    list   : List the AI models currently available to the model runner.
    test   : Tests the API using curl.
    start  : Starts running the docker model runner container in the background.
    stop   : Stops the docker model runner in the background.
"
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 ]]; then
	show_help
	exit 1
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

# Container name running the models. (Fixed by Docker plugin?)
dmr_container="docker-model-runner"
# The AI model used.
ai_model="ai/qwen3-coder:30B-A3B-UD-Q4_K_XL"
# Required packages.
declare -A packages
packages["Docker Model Plugin"]="docker-model-plugin"

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
		echo "Pulling the model: ${ai_model}"
		docker model pull "${ai_model}"
		;;

	run)
		docker model run "${ai_model}"
		;;

	start)
		docker model status
		;;

	list)
		docker model list
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
		curl http://localhost:12434/engines/llama.cpp/v1/chat/completions \
-H "Content-Type: application/json" \
-d "{
	\"model\": \"${ai_model}\",
	\"messages\": [
		{\"role\":\"system\",\"content\":\"You are a helpful coding assistant.\"},
		{\"role\":\"user\",\"content\":\"Create a simple CLI hello world app in Python?\"}
	],
	\"temperature\": 0.7,
	\"top_p\": 0.8,
	\"top_k\": 20,
	\"repetition_penalty\":1.05,
	\"max_tokens\":512
}"
		;;

	*)
		echo "Command '${cmd}' is invalid!"
		show_help
		exit 1
		;;
esac

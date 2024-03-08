#!/usr/bin/env bash

# On first error exit.
set -e

# Get the scripts directory.
#script_dir="$(cd "$( dirname "${BASH_SOURCE[0]}")" && pwd)"

# Virtual Python environment.
venv_dir="/usr/local/lib/gcovr"
# Command file for passing to virtual environment.
cmd_file="/usr/local/bin/gcovr"

# Packages needed to be installed.
pkgs=("python3" "python3-venv")

# Iterate through the packages one by one. ()
for pkg in "${pkgs[@]}"; do
	# Check if a package is installed by checking the package listing string.
	if [[ "$(apt -qq list "${pkg}" 2>/dev/null | head -n 1)" =~ (\[installed\]) ]]; then
		echo "Package '${pkg}' already installed..."
		continue
	fi
	# Perform the install of the package.
	if ! apt-get --yes install "${pkg}"; then
		echo "Install of package '${pkg}' failed!"
		exit 1
	fi
done

# When the directory does not exists.
if [[ ! -d "${venv_dir}" ]]; then
	# Create the virtual environment.
	python3 -m venv "${venv_dir}"
fi

# Activate the virtual environment.
source "${venv_dir}/bin/activate"

# Install the application when not installed.
if ! python3 -c "import gcovr" 2>/dev/null; then
	pip install gcovr
fi

# Create script for global use.
echo "Create gcov script for global use..."
cat <<EOF > "${cmd_file}" && chmod +x "${cmd_file}"
#!/usr/bin/env bash
source "${venv_dir}/bin/activate"
${venv_dir}/bin/gcovr "\${@}"
deactivate
EOF

# Deactivate the virtual environment.
deactivate

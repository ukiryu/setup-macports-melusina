# macports.sh — Functions for MacPorts

# Melusina Actions (https://github.com/melusina-org/setup-macports)
# This file is part of Melusina Actions.
#
# Copyright © 2022–2023 Michaël Le Barbier
# All rights reserved.

# This file must be used under the terms of the MIT License.
# This source file is licensed as described in the file LICENSE, which
# you should have received as part of this distribution. The terms
# are also available at https://opensource.org/licenses/MIT

: ${macports_owner:=$(id -u -n)}
: ${macports_group:=$(id -g -n)}
: ${macports_version:='2.11.5'}
: ${macports_prefix:='/opt/local'}

macports_install()
{
    install -o "${macports_owner}" -g "${macports_group}" "$@"
}

configuration_summary()
{
    cat <<SUMMARY
Package: $(make_package)
Prefix: ${macports_prefix}
Version: ${macports_version}
Variants: $(variants_document)
Ports: $(ports_document)
Sources: $(sources_document)
Path: ${PATH}
Parameter File: ${parameterfile}
SUMMARY
}

write_configuration()
{
    local pathname macos
    pathname="$2"

    macports_install -d -m 755 $(dirname "${pathname}")
    macports_install -m 644 /dev/null "${pathname}"

    if [ -f "$1" -a -r "$1" ]; then
	cp -f "$1" "${pathname}"
    elif [ "$1" = ':no-value' ]; then
	cat > "${pathname}" <<YAML
version: "${macports_version}"
prefix: "${macports_prefix}"
YAML
    else
	failwith '%s: Not a regular and readable file.' "$1"
    fi

    with_group_presentation\
	'Configuration Summary'\
	configuration_summary
}

variants_document()
{
    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    printf '# MacPorts system-wide global variants configuration file.\n'
    yq '
.variants // {}
| ( .select = .select // [] )
| ( .select = select(.select | type == "!!seq").select // [.select] )
| ( .deselect = .deselect || [] )
| ( .deselect = select(.deselect | type == "!!seq").deselect || [.deselect] )
| (
    (.select | .[] | "+" + . ),
    (.deselect | .[] | "-" + . )
  )
' < "$1"
}

ports_document()
{
    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    yq '
.ports // {} | .[]
| ( .select = .select || [] )
| ( .select = select(.select | type == "!!seq").select || [.select] )
| ( .select = (.select | map("+" + . ) | join(" ")))
| ( .deselect = .deselect || [] )
| ( .deselect = select(.deselect | type == "!!seq").deselect || [.deselect] )
| ( .deselect = (.deselect | map("-" + . ) | join(" ")))
| ( [ .name, .select, .deselect ] | join (" "))
' < "$1"
}

sources_document()
{
    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    yq '
.sources // ["rsync://rsync.macports.org/macports/release/tarballs/ports.tar"]
| ( .[0] = .[0] + " [default]")
| .[]
' < "$1"
}

write_variants()
{
    macports_install -d -m 755 "${macports_prefix}/etc/macports"
    macports_install -m 644 /dev/null "${macports_prefix}/etc/macports/variants.conf"
    variants_document "$1" > "${macports_prefix}/etc/macports/variants.conf"
}

write_sources()
{
    macports_install -d -m 755 "${macports_prefix}/etc/macports"
    macports_install -m 644 /dev/null "${macports_prefix}/etc/macports/sources.conf"

    if [ "$#" -eq 0 ]; then
	set -- "${macports_prefix}/etc/setup-macports.yaml"
    fi

    # Check if the first source is a git URL
    local first_source
    first_source=$(yq '.sources[0] // "rsync://rsync.macports.org/macports/release/tarballs/ports.tar"' < "$1")

    if is_git_url "${first_source}"; then
	# Use git-based sources
	# Extract owner and repo from GitHub URL
	# e.g., https://github.com/macports/macports-ports.git -> macports/macports-ports
	local repo_owner repo_name local_path
	repo_owner=$(printf '%s' "${first_source}" | sed -E 's|^.*/([^/]+)/([^/]+)(\.git)?$|\1|')
	repo_name=$(printf '%s' "${first_source}" | sed -E 's|^.*/([^/]+)/([^/]+)(\.git)?$|\2|')

	# Local path following MacPorts convention
	local_path="${macports_prefix}/var/macports/sources/github.com/${repo_owner}/${repo_name}"

	# Check if the repository has been checked out (e.g., by actions/checkout)
	if [ -d "${local_path}/.git" ]; then
	    wlog 'Info' "Using existing git sources at ${local_path}"
	    printf 'file://%s/ [default]\n' "${local_path}" > "${macports_prefix}/etc/macports/sources.conf"
	else
	    wlog 'Warning' "Git sources specified but repository not found at ${local_path}"
	    wlog 'Warning' "Please checkout the repository first using actions/checkout"
	    wlog 'Warning' "Falling back to rsync sources"
	    sources_document "$1" > "${macports_prefix}/etc/macports/sources.conf"
	fi
    else
	# Use traditional sources
	sources_document "$1" > "${macports_prefix}/etc/macports/sources.conf"
    fi
}

# Check if a URL is a git URL (https://github.com/... or git://...)
is_git_url()
{
    case "$1" in
	https://github.com/*/*|git@github.com:*/*|git://github.com/*/*)
	    return 0
	    ;;
	*)
	    return 1
	    ;;
    esac
}

make_package()
{
    local macos version

    case $# in
	0)
	    macos=$(probe_macos)
	    version=$(yq ".version || \"${macports_version}\"" < "${macports_prefix}/etc/setup-macports.yaml")
	    ;;
	1)
	    macos=$(probe_macos)
 	    version=$(yq ".version || \"${macports_version}\"" < "$1")
	    ;;
	2)
	    macos="$1"
	    version="$2"
	    ;;
    esac
    known_macos_db | awk -F'-' "-vmacos=${macos}" "-vversion=${version}" '
$2 == macos {
  printf("https://github.com/macports/macports-base/releases/download/v%s/MacPorts-%s-%s-%s.pkg", version, version, $1, $2)
}
'
}

# Check if a URL is a git URL (https://github.com/... or git://...)
is_git_url()
{
    case "$1" in
	https://github.com/*/*|git@github.com:*/*|git://github.com/*/*)
	    return 0
	    ;;
	*)
	    return 1
	    ;;
    esac
}

# End of file `macports.sh'

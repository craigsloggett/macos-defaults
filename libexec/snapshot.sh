#!/bin/sh
#
# libexec/snapshot.sh
#
# Capture every preference domain so that two snapshots taken either side of a
# System Settings change can be diffed to find the domain and key behind a
# toggle.
#
# Snapshots hold access tokens, account identifiers and the hardware UUID, so
# they are written under XDG_STATE_HOME rather than into a repository.

set -euf

: "${MACOS_DEFAULTS_SNAPSHOTS:?a snapshots directory is required}"

# die reports a fatal error on stderr and aborts the script.
die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# list_user_domains prints one per-user domain, prepending the global domain
# that `defaults domains` omits from its output.
list_user_domains() (
  printf '%s\n' 'NSGlobalDomain'
  defaults domains | tr ',' '\n' | sed 's/^[[:space:]]*//'
)

# export_domains reads domain names on stdin and writes each as XML into the
# given directory. `defaults export` emits key-sorted XML that is byte-stable
# across reads, so no normalisation pass is needed for a clean diff. System
# domains arrive as absolute paths, so the file is named for the basename; no
# user domain contains a slash, which keeps the two cases consistent.
export_domains() (
  directory="${1:?a directory is required}"
  shift

  mkdir -p "${directory}"

  while read -r domain; do
    defaults "$@" export "${domain}" - >"${directory}/${domain##*/}.plist"
  done
)

# snapshot_system copies the machine-wide preferences, which are readable
# without sudo even though writing them is not.
snapshot_system() (
  directory="${1:?a directory is required}"

  find /Library/Preferences -maxdepth 1 -name '*.plist' |
    sed 's|\.plist$||' |
    export_domains "${directory}"
)

main() {
  command -v defaults >/dev/null 2>&1 || die 'defaults is required'

  label="${1:?a snapshot label is required}"
  snapshot_dir="${MACOS_DEFAULTS_SNAPSHOTS}/${label}"

  rm -rf "${snapshot_dir}"

  list_user_domains | export_domains "${snapshot_dir}/user"
  defaults -currentHost domains | tr ',' '\n' | sed 's/^[[:space:]]*//' |
    export_domains "${snapshot_dir}/byhost" -currentHost
  snapshot_system "${snapshot_dir}/system"

  printf '%s\n' "Snapshot written to ${snapshot_dir}"
}

main "$@"

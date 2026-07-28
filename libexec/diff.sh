#!/bin/sh
#
# libexec/diff.sh
#
# Compare two snapshots. With no domain arguments it prints the name of every
# domain that changed, one per line, so a run can be subtracted from a noise
# baseline with `grep -vxF -f`. Pass domain names to see the hunks instead.

set -euf

: "${MACOS_DEFAULTS_ROOT:?the root directory is required}"
: "${MACOS_DEFAULTS_SNAPSHOTS:?a snapshots directory is required}"

readonly NOISE_FILE="${MACOS_DEFAULTS_ROOT}/share/noise.conf"

# die reports a fatal error on stderr and aborts the script.
die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# strip_noise removes the keys listed in noise.conf, and the single line holding
# each one's value, from every plist under source_dir.
strip_noise() (
  source_dir="${1:?a source directory is required}"
  target_dir="${2:?a target directory is required}"

  cd "${source_dir}" || return 1

  find . -name '*.plist' | while read -r plist; do
    mkdir -p "${target_dir}/${plist%/*}"

    awk '
      BEGIN {
        key_open = "<key>"
        key_close = "</key>"
        key_line_pattern = key_open "[^<]*" key_close
      }
      FNR == NR {                                  # First file: the noise list.
        if ($0 !~ /^[[:space:]]*(#|$)/) { noisy[$0] = 1 }
        next
      }
      match($0, key_line_pattern) {
        key = substr($0, RSTART + length(key_open), \
          RLENGTH - length(key_open) - length(key_close))
        if (key in noisy) {
          getline                                  # Drop the value line too.
          next
        }
      }
      { print }
    ' "${NOISE_FILE}" "${plist}" >"${target_dir}/${plist}"
  done
)

# list_names prints the relative name, without the .plist suffix, of every
# domain matching the given pattern in either tree, so domains added or removed
# between the two snapshots are considered alongside those that changed.
list_names() (
  before="${1:?a before directory is required}"
  after="${2:?an after directory is required}"
  pattern="${3:?a pattern is required}"

  {
    (cd "${before}" && find . -name "${pattern}")
    (cd "${after}" && find . -name "${pattern}")
  } | sed -e 's|^\./||' -e 's|\.plist$||' | sort -u
)

# diff_domain prints a unified diff for one domain, standing in /dev/null for
# whichever side is absent so an added or removed domain shows in full.
diff_domain() (
  before="${1:?a before file is required}"
  after="${2:?an after file is required}"

  [ -f "${before}" ] || before=/dev/null
  [ -f "${after}" ] || after=/dev/null

  diff -u "${before}" "${after}" || :
)

main() {
  command -v awk >/dev/null 2>&1 || die 'awk is required'
  [ -f "${NOISE_FILE}" ] || die "missing ${NOISE_FILE}"

  before_label="${1:?a before snapshot label is required}"
  after_label="${2:?an after snapshot label is required}"
  shift 2

  [ -d "${MACOS_DEFAULTS_SNAPSHOTS}/${before_label}" ] || die "no such snapshot: ${before_label}"
  [ -d "${MACOS_DEFAULTS_SNAPSHOTS}/${after_label}" ] || die "no such snapshot: ${after_label}"

  workdir="$(mktemp -d)"
  readonly workdir
  trap 'rm -rf "${workdir}"' EXIT INT TERM HUP

  strip_noise "${MACOS_DEFAULTS_SNAPSHOTS}/${before_label}" "${workdir}/before"
  strip_noise "${MACOS_DEFAULTS_SNAPSHOTS}/${after_label}" "${workdir}/after"

  if [ "$#" -eq 0 ]; then
    list_names "${workdir}/before" "${workdir}/after" '*.plist' |
      while read -r domain; do
        cmp -s "${workdir}/before/${domain}.plist" \
          "${workdir}/after/${domain}.plist" 2>/dev/null ||
          printf '%s\n' "${domain}"
      done
    return 0
  fi

  for domain in "$@"; do
    list_names "${workdir}/before" "${workdir}/after" "${domain}.plist" |
      while read -r relative; do
        diff_domain "${workdir}/before/${relative}.plist" \
          "${workdir}/after/${relative}.plist"
      done
  done
}

main "$@"

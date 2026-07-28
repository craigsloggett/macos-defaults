#!/bin/sh
#
# bin/macos-defaults.sh
#
# Front end for the macos-defaults subcommands. It resolves where the tool's own
# data lives, parses the options every subcommand shares, and hands off.
#
# MACOS_DEFAULTS_ROOT is set by the Homebrew wrapper, because $0 there is a
# symlink in the prefix bin and resolving it would not find share/.

set -euf

: "${XDG_STATE_HOME:=${HOME}/.local/state}"
: "${MACOS_DEFAULTS_ROOT:=$(cd "${0%/*}/.." && printf '%s\n' "${PWD}")}"

readonly MACOS_DEFAULTS_ROOT

# die reports a fatal error on stderr and aborts the script.
die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# usage prints the help text.
usage() {
  cat <<'EOF'
Usage: macos-defaults <command> [options] [arguments]

Commands:
  apply                    Write every recorded setting that differs from the
                           live system, then restart only the affected processes.
  check                    Report drift and exit non-zero. Changes nothing.
  lint                     Validate the records as text. Needs no macOS.
  snapshot <label>         Capture every preference domain under a label.
  diff <before> <after> [domain...]
                           List the domains that differ between two snapshots,
                           or show the hunks for the domains named.
  doctor                   Report on the setup steps that cannot be scripted.

Options:
  -s, --settings DIR       Directory holding the .conf records.
                           Default: ./settings
  -d, --snapshots DIR      Where snapshots are written.
                           Default: $XDG_STATE_HOME/macos-defaults/snapshots
  -h, --help               Show this message.

Records are tab separated (domain, key, type, value). See the README.
EOF
}

main() {
  command="${1:-}"
  [ -n "${command}" ] || {
    usage >&2
    return 1
  }
  shift

  case "${command}" in
    -h | --help | help)
      usage
      return 0
      ;;
  esac

  settings='./settings'
  snapshots="${XDG_STATE_HOME}/macos-defaults/snapshots"
  operands=''

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -s | --settings)
        settings="${2:?a settings directory is required}"
        shift 2
        ;;
      -d | --snapshots)
        snapshots="${2:?a snapshots directory is required}"
        shift 2
        ;;
      -h | --help)
        usage
        return 0
        ;;
      -*) die "unknown option: $1" ;;
      *)
        operands="${operands} $1"
        shift
        ;;
    esac
  done

  export MACOS_DEFAULTS_ROOT
  MACOS_DEFAULTS_SETTINGS="${settings}"
  MACOS_DEFAULTS_SNAPSHOTS="${snapshots}"
  export MACOS_DEFAULTS_SETTINGS MACOS_DEFAULTS_SNAPSHOTS

  # Operands are snapshot labels and domain names, neither of which contains a
  # space, so rebuilding the argument list from a string is safe here.
  # shellcheck disable=SC2086
  set -- ${operands}

  case "${command}" in
    apply | check | lint) "${MACOS_DEFAULTS_ROOT}/libexec/apply.sh" "${command}" ;;
    snapshot) "${MACOS_DEFAULTS_ROOT}/libexec/snapshot.sh" "$@" ;;
    diff) "${MACOS_DEFAULTS_ROOT}/libexec/diff.sh" "$@" ;;
    doctor) "${MACOS_DEFAULTS_ROOT}/libexec/doctor.sh" ;;
    *) die "unknown command: ${command}" ;;
  esac
}

main "$@"

#!/bin/sh
#
# libexec/apply.sh
#
# Reconcile the recorded settings with the live system, restarting only the
# processes that own a domain which actually changed.
#
# `defaults write` returns 0 for a key macOS no longer reads, so a write-only
# script cannot report that it has stopped working. Keeping the settings as data
# is what makes `check` possible, which is the only thing that detects that rot,
# and `lint`, which catches a mistyped domain or key without needing a Mac.

set -euf

: "${MACOS_DEFAULTS_ROOT:?the root directory is required}"
: "${MACOS_DEFAULTS_SETTINGS:?a settings directory is required}"

readonly VALID_TYPES='bool int float string'
readonly SHARED_RESTART="${MACOS_DEFAULTS_ROOT}/share/restart.conf"
readonly LOCAL_RESTART="${MACOS_DEFAULTS_SETTINGS}/restart.conf"

# die reports a fatal error on stderr and aborts the script.
die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# restart_files prints the restart maps to consult, most specific first, so a
# host can override or extend the map the tool ships with.
restart_files() (
  [ -f "${LOCAL_RESTART}" ] && printf '%s\n' "${LOCAL_RESTART}"
  printf '%s\n' "${SHARED_RESTART}"
)

# read_default prints the live value of a domain and key, or nothing when the
# pair is unset. Reads go through defaults so they observe cfprefsd's
# authoritative state rather than a stale on-disk plist.
read_default() (
  defaults read "${1:?a domain is required}" "${2:?a key is required}" 2>/dev/null || return 0
)

# read_type prints the live type of a key in this tool's vocabulary, or nothing
# when the key is unset. A bool and an int both read as 1, so without this a
# record naming the wrong type looks settled while applying it would rewrite the
# key with the wrong type.
read_type() (
  live="$(defaults read-type "${1:?a domain is required}" "${2:?a key is required}" 2>/dev/null)" ||
    return 0

  case "${live}" in
    'Type is boolean') printf '%s\n' 'bool' ;;
    'Type is integer') printf '%s\n' 'int' ;;
    'Type is float') printf '%s\n' 'float' ;;
    'Type is string') printf '%s\n' 'string' ;;
    *) printf '%s\n' "${live#Type is }" ;;
  esac
)

# desired_value prints a recorded value in the form `defaults read` reports it,
# so the two compare as plain strings. Booleans are the only type whose write
# syntax and read output differ.
desired_value() (
  type="${1:?a type is required}"
  value="${2?a value is required}"

  case "${type}:${value}" in
    bool:true | bool:yes | bool:1) printf '%s\n' '1' ;;
    bool:false | bool:no | bool:0) printf '%s\n' '0' ;;
    bool:*) return 1 ;;
    *) printf '%s\n' "${value}" ;;
  esac
)

# lint_records prints one line per malformed record, prefixed with its file and
# line number. It never calls defaults, so it runs on a Linux CI runner.
lint_records() (
  known="$(restart_files | xargs cat)"

  find "${MACOS_DEFAULTS_SETTINGS}" -name '*.conf' ! -name 'restart.conf' | sort |
    while read -r file; do
      printf '%s\n' "${known}" | awk -v valid_types="${VALID_TYPES}" '
        BEGIN {
          type_count = split(valid_types, types, " ")
          for (i = 1; i <= type_count; i++) { is_type[types[i]] = 1 }
          trailing_space_pattern = "[ \t]$"
          bool_pattern = "^(true|false|yes|no|0|1)$"
        }
        /^[[:space:]]*(#|$)/ { next }
        FILENAME == "-" { known_domain[$1] = 1; next }
        {
          where = FILENAME ":" FNR
          if ($0 ~ trailing_space_pattern) { print where ": trailing whitespace" }
          if (NF < 4) { print where ": expected 4 fields, found " NF; next }
          if (!($3 in is_type)) { print where ": unknown type: " $3 }
          if ($3 != "string" && NF != 4) { print where ": " $3 " value must not contain spaces" }
          if ($3 == "bool" && $4 !~ bool_pattern) { print where ": not a bool: " $4 }
          if (!($1 in known_domain)) { print where ": domain missing from restart.conf: " $1 }
        }
      ' - "${file}"
    done
)

# plan prints a record for every setting whose live value or type differs from
# the recorded one. Globbing is off under set -f, so files are walked with find.
plan() (
  find "${MACOS_DEFAULTS_SETTINGS}" -name '*.conf' ! -name 'restart.conf' | sort |
    while read -r file; do
      while read -r domain key type value; do
        case "${domain}" in '' | '#'*) continue ;; esac

        want="$(desired_value "${type}" "${value}")" ||
          die "${file}: not a valid ${type}: ${value}"

        if [ "${want}" = "$(read_default "${domain}" "${key}")" ] &&
          [ "${type}" = "$(read_type "${domain}" "${key}")" ]; then
          continue
        fi

        printf '%s\t%s\t%s\t%s\n' "${domain}" "${key}" "${type}" "${value}"
      done <"${file}"
    done
)

# apply_plan writes each record read on stdin and prints the domain it touched,
# so the caller can restart exactly the affected processes.
apply_plan() (
  while read -r domain key type value; do
    defaults write "${domain}" "${key}" "-${type}" "${value}"
    printf '%s\n' "${domain}"
  done
)

# restart_processes restarts the owner of each domain read on stdin. Only
# changed domains reach here, so a re-run relaunches nothing, which is what
# keeps the tool safe to run on a schedule.
restart_processes() (
  maps="$(restart_files | xargs cat)"

  sort -u | while read -r domain; do
    process="$(printf '%s\n' "${maps}" | awk -v domain="${domain}" '$1 == domain { print $2; exit }')"

    case "${process}" in
      none) : ;;
      '') printf '%s\n' "No restart mapped for ${domain}." ;;
      logout) printf '%s\n' "Log out to apply changes to ${domain}." ;;
      # The owning process may legitimately not be running yet.
      *) killall "${process}" 2>/dev/null || : ;;
    esac
  done
)

main() {
  mode="${1:?a mode is required}"

  [ -d "${MACOS_DEFAULTS_SETTINGS}" ] ||
    die "no such settings directory: ${MACOS_DEFAULTS_SETTINGS}"
  [ -f "${SHARED_RESTART}" ] || die "missing ${SHARED_RESTART}"

  if [ "${mode}" = 'lint' ]; then
    problems="$(lint_records)"
    [ -n "${problems}" ] || return 0
    printf '%s\n' "${problems}" >&2
    return 1
  fi

  command -v defaults >/dev/null 2>&1 || die 'defaults is required'

  changed="$(plan)"
  [ -n "${changed}" ] || return 0

  if [ "${mode}" = 'check' ]; then
    printf '%s\n' "${changed}"
    return 1
  fi

  printf '%s\n' "${changed}" | apply_plan | restart_processes
}

main "$@"

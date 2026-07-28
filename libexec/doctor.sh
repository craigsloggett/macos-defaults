#!/bin/sh
#
# libexec/doctor.sh
#
# Report on the settings that cannot be scripted at all: TCC grants, FileVault,
# iCloud, Touch ID enrollment and the rest.
#
# A checklist nobody re-reads rots, so everything observable is asserted here
# instead. This always exits 0: these are human actions, and a check that blocks
# an install is a check that gets deleted.
#
# Every assertion must be silent and non-interactive. `sfltool dumpbtm` would
# cover login items but prompts for admin credentials, so it is not used.

set -euf

# assert reports whether a prerequisite is in place, using the command's exit
# status.
assert() (
  description="${1:?a description is required}"
  shift

  if "$@" >/dev/null 2>&1; then
    printf 'ok    %s\n' "${description}"
  else
    printf 'TODO  %s\n' "${description}"
  fi
)

# assert_match reports on a prerequisite whose command succeeds either way, so
# the answer is in its output rather than its exit status.
assert_match() (
  description="${1:?a description is required}"
  pattern="${2:?a pattern is required}"
  shift 2

  if "$@" 2>/dev/null | grep -q "${pattern}"; then
    printf 'ok    %s\n' "${description}"
  else
    printf 'TODO  %s\n' "${description}"
  fi
)

# tcc_granted reports whether this terminal holds Full Disk Access, using the
# TCC database as the canary since reading it requires exactly that grant.
tcc_granted() (
  ls "${HOME}/Library/Application Support/com.apple.TCC"
)

# pam_reattach_installed reports whether the module that makes Touch ID work
# inside tmux is present, checking both Homebrew prefixes.
pam_reattach_installed() {
  [ -f /opt/homebrew/lib/pam/pam_reattach.so ] ||
    [ -f /usr/local/lib/pam/pam_reattach.so ]
}

main() {
  [ "$(uname -s)" = 'Darwin' ] || return 0

  printf '%s\n' 'Setup that cannot be scripted:'

  assert_match 'FileVault is on' 'FileVault is On' fdesetup status
  assert_match 'System Integrity Protection is on' 'enabled' csrutil status
  assert_match 'Touch ID is enrolled' 'Biometrics for unlock: 1' bioutil -r
  assert 'Signed in to iCloud' defaults read MobileMeAccounts Accounts

  assert 'Touch ID authorises sudo' [ -f /etc/pam.d/sudo_local ]
  assert 'Touch ID works inside tmux' pam_reattach_installed

  assert_match 'Developer mode is enabled' 'enabled' DevToolsSecurity -status
  assert_match 'Firewall is on' 'State = 1' \
    /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

  assert 'Terminal has Full Disk Access' tcc_granted

  printf '%s\n' 'Login items, privacy grants and the default browser need a human.'
}

main "$@"

#!/bin/sh

set -eu

download_url='https://ii.n1cat.xyz/downloads/iimod/linux-x86_64'
checksum_url="${download_url}.sha256"
destination='/usr/local/bin/iimod'

printf '%s\n' \
  'iimod CLI installer for Linux x86_64' \
  "This will install the official iimod binary to ${destination}." \
  'The binary will be downloaded over HTTPS and its SHA256 checksum will be verified.' \
  'Installation stops if checksum verification fails.' \
  'After verification, sudo may request your password to install the file.' \
  ''

for command_name in cat curl mktemp sha256sum sudo install uname; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
done

system_name="$(uname -s)"
machine_name="$(uname -m)"
case "${system_name}/${machine_name}" in
  Linux/x86_64|Linux/amd64) ;;
  *)
    printf 'Unsupported platform: %s/%s. Build iimod from source instead.\n' \
      "$system_name" "$machine_name" >&2
    exit 1
    ;;
esac

umask 077
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
binary_path="${tmp_dir}/iimod"
checksum_path="${tmp_dir}/iimod.sha256"

printf '%s\n' 'Downloading iimod and checksum...'
curl --fail --location --proto '=https' --tlsv1.2 --progress-bar \
  --output "$binary_path" "$download_url"
curl --fail --location --proto '=https' --tlsv1.2 --progress-bar \
  --output "$checksum_path" "$checksum_url"

checksum="$(cat "$checksum_path")"
case "$checksum" in
  ''|*[!0-9a-fA-F]*)
    printf '%s\n' 'Invalid checksum response; installation stopped.' >&2
    exit 1
    ;;
esac
if [ "${#checksum}" -ne 64 ]; then
  printf '%s\n' 'Invalid checksum response; installation stopped.' >&2
  exit 1
fi

if ! (cd "$tmp_dir" && printf '%s  %s\n' "$checksum" 'iimod' | sha256sum --check --status -); then
  printf '%s\n' 'Checksum verification failed; installation stopped.' >&2
  exit 1
fi

printf '%s\n' \
  'Checksum verified.' \
  "Installing iimod to ${destination}; sudo may now request your password..."
sudo install -m 0755 "$binary_path" "$destination"
printf '%s\n' 'Installation complete. Next: choose a module below and run its install command.'

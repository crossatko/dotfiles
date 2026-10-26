#!/bin/bash
# Arch Linux installer for these dotfiles. Idempotent: every step checks the current state first and a second
# run changes nothing. Never run it as root (it calls sudo itself where needed).
#
#   ./install.sh [--dry-run] [--yes] [--only STAGE[,STAGE...]] [--with BUNDLE[,BUNDLE...]] [--repos] [--system] [--chsh] [-h|--help]
#
# Stages (run in this order):
#   repos     (sudo, opt-in) third-party repos on top of Arch: CachyOS (arch-optimised + [cachyos]) and Chaotic-AUR
#   packages  multilib, yay, packages/{pacman,aur,flatpak}.txt, plus opt-in bundles packages/optional/NAME.txt (--with NAME)
#   links     symlinks into $HOME, shell dotfiles, GTK seed, theme seed, web apps, librepods build
#   system    (sudo) system/etc files, udev rules, /etc/environment host marker, services, ufw, docker group
# Default: packages + links. `repos` and `system` are opt-in: --repos / --system, or --only (e.g. `--only repos,packages,links`).
#
# Environment: CLAUDE_TABS_DIR (claude-tabs checkout), INSTALL_SKIP (space separated: librepods omz claude-tabs
# cachyos-repo chaotic-repo), GPU_DRIVER (radeon|intel|virtio|swrast|none instead of GPU detection), PACMAN_CONF (pacman.conf to edit, default /etc/pacman.conf; for tests),
# CACHYOS_LEVEL (force znver4|v4|v3|plain|none instead of CPU detection).
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"
PKG_DIR="$DOTFILES_DIR/packages"
PACMAN_CONF="${PACMAN_CONF:-/etc/pacman.conf}"
SYS_DIR="$DOTFILES_DIR/system/etc"

DRY=0
YES=0
CHSH=0
WANT_SYSTEM=0
WANT_REPOS=0
ONLY=""
WITH=""
BUNDLES=()
CHANGES=0
FONTS_DIRTY=0
STAMP="$(date +%Y%m%d-%H%M%S)"
INSTALL_SKIP="${INSTALL_SKIP:-}"
TMP_DIRS=()
KEEPALIVE_PID=

bundle_names() {
  local f
  for f in "$PKG_DIR"/optional/*.txt; do
    [ -e "$f" ] && { f="${f##*/}"; echo "${f%.txt}"; }
  done
}

bundle_help() {
  local b d
  while IFS= read -r b; do
    d="$(sed -n '1s/^# Optional bundle: //p' "$PKG_DIR/optional/$b.txt")"
    printf '  %-16s %s\n' "$b" "${d%.}"
  done < <(bundle_names)
}

usage() {
  cat <<EOF
Usage: ./install.sh [--dry-run] [--yes] [--only STAGE[,STAGE...]] [--with BUNDLE[,BUNDLE...]] [--repos] [--system] [--chsh] [-h|--help]

Arch Linux only. Idempotent; never run as root.

Stages:
  repos     (sudo, opt-in) add the third-party CachyOS repos (arch-optimised core/extra rebuilds + [cachyos]) and
            Chaotic-AUR to pacman.conf, with their keys, keyrings and mirrorlists. Does NOT install the CachyOS
            kernel. The repos sit above [core]/[extra], so the next -Syu may swap in optimised rebuilds.
            Opt-in because no package in packages/*.txt needs it.
  packages  enable multilib, bootstrap yay, install packages/pacman.txt, packages/aur.txt, packages/flatpak.txt,
            then the optional bundles chosen with --with
  links     symlink config into $HOME (backs up real files once), shell dotfiles, GTK seed, theme seed,
            git hooks, web apps, librepods build
  system    (sudo) install system/etc files (udev rules, ...), /etc/environment host marker, enable services,
            ufw, docker group

Options:
  --dry-run        print every action, change nothing, do not call sudo
  --yes            pass --noconfirm to pacman/yay (no questions; default: pacman asks, unless stdin is not a terminal)
  --only STAGES    comma separated subset of: repos,packages,links,system
  --with BUNDLES   also install optional bundles (comma separated, or 'all'), see below; runs the packages stage
  --repos          also run the repos stage (default stages: packages,links)
  --system         also run the system stage
  --chsh           change the login shell to zsh (asks for your password)
  -h, --help       this text

Optional bundles (packages/optional/NAME.txt, not installed by default):
$(bundle_help)

Environment:
  GPU_DRIVER=radeon|intel|virtio|swrast|none
                   GPU stack for the packages stage (mesa, Vulkan driver, lib32 variants; Intel adds
                   intel-media-driver) instead of detecting it with lspci. Detected: AMD -> radeon, Intel ->
                   intel, QEMU/virtio -> virtio, anything else (VMware, VirtualBox, NVIDIA, unknown) ->
                   swrast; several GPUs install all matching. NVIDIA is not supported by this installer.
                   none = no GPU driver. amd-ucode/intel-ucode is added on bare metal (not with none).
  INSTALL_SKIP, CLAUDE_TABS_DIR, PACMAN_CONF, CACHYOS_LEVEL   see the header of install.sh
EOF
}

die() { echo "install.sh: $*" >&2; exit 1; }
log() { echo "==> $*"; }
info() { echo "    $*"; }
warn() { echo "    warning: $*" >&2; }
changed() { CHANGES=$((CHANGES + 1)); }
skipped() { case " $INSTALL_SKIP " in *" $1 "*) return 0 ;; esac; return 1; }

cleanup() {
  local d
  if [ -n "$KEEPALIVE_PID" ]; then
    pkill -P "$KEEPALIVE_PID" 2>/dev/null || true
    kill "$KEEPALIVE_PID" 2>/dev/null || true
    wait "$KEEPALIVE_PID" 2>/dev/null || true
    KEEPALIVE_PID=
  fi
  for d in ${TMP_DIRS[@]+"${TMP_DIRS[@]}"}; do rm -rf "$d"; done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mktmp() {
  local d
  d="$(mktemp -d)"
  TMP_DIRS+=("$d")
  printf '%s\n' "$d"
}

# ---------------------------------------------------------------- args
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --yes | -y) YES=1 ;;
    --only)
      [ $# -ge 2 ] || die "--only needs a value"
      ONLY="$2"
      shift
      ;;
    --only=*) ONLY="${1#--only=}" ;;
    --with)
      [ $# -ge 2 ] || die "--with needs a value"
      WITH="$2"
      shift
      ;;
    --with=*) WITH="${1#--with=}" ;;
    --repos) WANT_REPOS=1 ;;
    --system) WANT_SYSTEM=1 ;;
    --chsh) CHSH=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

STAGES=()
if [ -n "$ONLY" ]; then
  IFS=',' read -r -a req <<<"$ONLY"
  for s in "${req[@]}"; do
    case "$s" in
      repos | packages | links | system) STAGES+=("$s") ;;
      *) die "unknown stage '$s' (repos, packages, links, system)" ;;
    esac
  done
else
  STAGES=(packages links)
fi
BUNDLES=()
if [ -n "$WITH" ]; then
  mapfile -t avail < <(bundle_names)
  IFS=',' read -r -a req <<<"$WITH"
  for s in "${req[@]}"; do
    if [ "$s" = all ]; then
      BUNDLES+=("${avail[@]}")
      continue
    fi
    case " ${avail[*]} " in
      *" $s "*) BUNDLES+=("$s") ;;
      *) die "unknown bundle '$s' (available: all ${avail[*]})" ;;
    esac
  done
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in
      *,packages,*) ;;
      *) die "--with installs packages, but --only '$ONLY' does not include the packages stage" ;;
    esac
  fi
fi
[ "$WANT_REPOS" = 1 ] && STAGES+=(repos)
[ "$WANT_SYSTEM" = 1 ] && STAGES+=(system)
stage_on() {
  local s
  for s in "${STAGES[@]}"; do [ "$s" = "$1" ] && return 0; done
  return 1
}

# ---------------------------------------------------------------- platform checks
if [ "$(uname -s)" = Darwin ]; then
  die "macOS is maintained by hand (see README.md); this installer is Arch-only."
fi
is_arch=0
[ -e /etc/arch-release ] && is_arch=1
if [ "$is_arch" = 0 ] && [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  if (. /etc/os-release && case " ${ID:-} ${ID_LIKE:-} " in *" arch "*) true ;; *) false ;; esac); then is_arch=1; fi
fi
[ "$is_arch" = 1 ] || die "this installer supports Arch Linux only."
[ "$(id -u)" -ne 0 ] || die "do not run as root; sudo is called where needed."
[ -n "${HOME:-}" ] || die "HOME is not set"

# ---------------------------------------------------------------- helpers
# run CMD...: print, and execute unless --dry-run. Counts as a change.
run() {
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] $*"
  else
    echo "    + $*"
    "$@"
  fi
}

# link SRC DEST: DEST becomes a symlink to SRC. Correct symlink: untouched. Wrong symlink: replaced.
# Real file/dir: moved to DEST.backup-<timestamp> once, then linked.
link() {
  local src="$1" dest="$2"
  [ -e "$src" ] || [ -L "$src" ] || { warn "missing source $src"; return 0; }
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "    ok      $dest"
    return 0
  fi
  changed
  if [ "$DRY" = 1 ]; then
    if [ -L "$dest" ]; then
      echo "    [dry-run] relink $dest -> $src (was $(readlink "$dest"))"
    elif [ -e "$dest" ]; then
      echo "    [dry-run] back up $dest to $dest.backup-$STAMP, link -> $src"
    else
      echo "    [dry-run] link $dest -> $src"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    mv "$dest" "$dest.backup-$STAMP"
    echo "    backed up $dest to $dest.backup-$STAMP"
  fi
  ln -s "$src" "$dest"
  echo "    linked  $dest -> $src"
}

# write_file DEST [MODE]: stdin becomes the content; rewritten only if it differs.
write_file() {
  local dest="$1" mode="${2:-644}" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    echo "    ok      $dest"
    return 0
  fi
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] write $dest"
  else
    mkdir -p "$(dirname "$dest")"
    [ -L "$dest" ] && rm -f "$dest"
    install -m "$mode" "$tmp" "$dest"
    echo "    wrote   $dest"
  fi
  rm -f "$tmp"
}

# seed_file DEST: write stdin only when DEST does not exist (the theme engine / the user own it afterwards).
# Returns 0 when it seeded (or would), 1 when DEST was left alone.
seed_file() {
  local dest="$1"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    cat >/dev/null
    echo "    ok      $dest (kept)"
    return 1
  fi
  write_file "$dest"
}

# sudo_install SRC DEST [MODE]: root-owned copy, only when the content differs.
sudo_install() {
  local src="$1" dest="$2" mode="${3:-644}"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "    ok      $dest"
    return 1
  fi
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] sudo install -Dm$mode -> $dest"
  else
    sudo install -Dm"$mode" "$src" "$dest"
    echo "    installed $dest"
  fi
  return 0
}

# read_list FILE: names without comments/blank lines, one per output line.
read_list() {
  [ -f "$1" ] || die "missing list $1"
  sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

PAC_FLAGS=(--needed)
{ [ -t 0 ] && [ "$YES" = 0 ]; } || PAC_FLAGS+=(--noconfirm)

# ================================================================= stage: repos
# Third-party repos on top of plain Arch, following the official procedures:
#   CachyOS  https://mirror.cachyos.org/cachyos-repo.tar.xz (cachyos-repo.sh): recv + lsign key, pacman -U keyring,
#            mirrorlists and CachyOS's patched pacman (needed for the x86_64_v3/v4 repos), then pacman.conf sections
#            above [core] (arch-optimised core/extra rebuilds + [cachyos]).
#   Chaotic  https://aur.chaotic.cx/docs: recv + lsign key, pacman -U keyring + mirrorlist, [chaotic-aur] appended.
# The script itself is never downloaded or run; only the documented steps are done here.
CACHYOS_KEY=882DCFE48E2051D48E2562ABF3B607488DB35A47 # short id F3B607488DB35A47 (official) # privacy-ok: public signing key
CHAOTIC_KEY=EF925EA60F33D0CB85C44AD13056513887B78AEB # short id 3056513887B78AEB (official) # privacy-ok: public signing key
KEYSERVER=keyserver.ubuntu.com
CACHYOS_MIRROR=https://mirror.cachyos.org/repo/x86_64/cachyos
CHAOTIC_MIRROR=https://cdn-mirror.chaotic.cx/chaotic-aur

# cachyos_level: znver4 | v4 | v3 | plain (no x86-64-v3: only [cachyos]) | none. Same method as cachyos-repo.sh: ld.so's supported ISA levels, and
# gcc -march=native for znver4/5 (without gcc: an AMD CPU with AVX-512 is Zen 4 or newer). CACHYOS_LEVEL overrides.
cachyos_level() {
  local ld cpu=""
  if [ -n "${CACHYOS_LEVEL:-}" ]; then
    printf '%s\n' "$CACHYOS_LEVEL"
    return 0
  fi
  ld="$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null || true)"
  if grep -q 'x86-64-v4 (supported, searched)' <<<"$ld"; then
    if command -v gcc >/dev/null 2>&1; then
      cpu="$(gcc -march=native -Q --help=target 2>&1 | grep march || true)"
      if grep -qE '(znver4|znver5)' <<<"$cpu"; then
        echo znver4
        return 0
      fi
    elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo 2>/dev/null && grep -q '^flags.*avx512f' /proc/cpuinfo 2>/dev/null; then
      echo znver4
      return 0
    fi
    echo v4
  elif grep -q 'x86-64-v3 (supported, searched)' <<<"$ld"; then
    echo v3
  else
    echo plain
  fi
}

# render_pacman_conf CONF LEVEL CHAOTIC(0|1): the edited pacman.conf on stdout; identical to CONF when nothing is to do.
# CachyOS sections go above the first repo section (before [core]), Chaotic goes last. Existing sections are left alone.
render_pacman_conf() {
  local conf="$1" level="$2" chaotic="$3" mirror suffix=""
  case "$level" in
    znver4) mirror=cachyos-v4-mirrorlist suffix=znver4 ;;
    v4) mirror=cachyos-v4-mirrorlist suffix=v4 ;;
    v3) mirror=cachyos-v3-mirrorlist suffix=v3 ;;
    *) mirror="" ;;
  esac
  if grep -q '^\[cachyos' "$conf"; then level=none; fi
  awk -v level="$level" -v suffix="$suffix" -v mirror="$mirror" -v chaotic="$chaotic" '
    function block(   s) {
      if (level == "none") return
      if (suffix != "") {
        print "[cachyos-" suffix "]\nInclude = /etc/pacman.d/" mirror "\n"
        print "[cachyos-core-" suffix "]\nInclude = /etc/pacman.d/" mirror "\n"
        print "[cachyos-extra-" suffix "]\nInclude = /etc/pacman.d/" mirror "\n"
      }
      print "[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n"
      done = 1; blank = 1
    }
    /^\[chaotic-aur\]/ { has_chaotic = 1 }
    /^\[options\]/ { in_opt = 1; print; next }
    /^\[[^]]+\]/ {
      if (in_opt && suffix != "" && !arch) { print "Architecture = auto"; arch = 1 }
      in_opt = 0
      if (!done && level != "none") { if (!blank && NR > 1) print ""; block() }
    }
    in_opt && suffix != "" && /^Architecture[ \t]*=/ {
      print "Architecture = auto"; arch = 1; next
    }
    { print; blank = ($0 == "") }
    END {
      if (!done && level != "none") { if (!blank) print ""; block() }
      if (chaotic == 1 && !has_chaotic) {
        if (!blank) print ""
        print "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist"
      }
    }
  ' "$conf"
}

# repo_key FPR LABEL: import and locally sign a signing key unless it is already trusted.
repo_key() {
  local fpr="$1" label="$2"
  if pacman-key --list-keys "$fpr" 2>/dev/null | grep -qE '\[ *(full|ultimate) *\]'; then
    echo "    ok      $label signing key trusted"
    return 0
  fi
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] sudo pacman-key --recv-keys $fpr --keyserver $KEYSERVER"
    echo "    [dry-run] sudo pacman-key --lsign-key $fpr"
  else
    sudo pacman-key --recv-keys "$fpr" --keyserver "$KEYSERVER"
    sudo pacman-key --lsign-key "$fpr"
  fi
}

# cachyos_pkg_url NAME: URL of the newest NAME-<version>-*.pkg.tar.zst in the official CachyOS mirror directory.
cachyos_pkg_url() {
  local name="$1" listing file
  listing="$(curl -fsSL --max-time 30 "$CACHYOS_MIRROR/")" || return 1
  file="$(grep -oE "href=\"$name-[0-9][^\"]*\\.pkg\\.tar\\.zst\"" <<<"$listing" | sed -e 's/^href="//' -e 's/"$//' | sort -V | tail -n 1)"
  [ -n "$file" ] || return 1
  printf '%s/%s\n' "$CACHYOS_MIRROR" "$file"
}

stage_repos() {
  log "Stage repos (third-party package repositories)"
  echo "    This adds the CachyOS and Chaotic-AUR repos to $PACMAN_CONF (third-party, signed by keys that are"
  echo "    locally trusted here). The CachyOS kernel is NOT installed. The arch-optimised repos sit above"
  echo "    [core]/[extra], so the next -Syu can replace Arch packages with optimised rebuilds."

  local level want_cachyos=1 want_chaotic=1 pkgs=() url n
  skipped cachyos-repo && want_cachyos=0
  skipped chaotic-repo && want_chaotic=0

  if [ "$want_cachyos" = 1 ]; then
    if grep -q '^\[cachyos' "$PACMAN_CONF"; then
      echo "    ok      CachyOS repos already in $PACMAN_CONF"
      level=none
    else
      level="$(cachyos_level)"
      case "$level" in
        znver4 | v4 | v3) info "CPU level: $level (arch-optimised repos + [cachyos])" ;;
        plain) info "CPU level: no x86-64-v3 support, adding only the plain [cachyos] repo" ;;
        none) ;;
        *) die "bad CACHYOS_LEVEL '$level' (znver4, v4, v3, plain, none)" ;;
      esac
    fi
  else
    level=none
  fi

  # 1. keys (signature checks of everything below rely on them)
  [ "$want_cachyos" = 1 ] && repo_key "$CACHYOS_KEY" CachyOS
  [ "$want_chaotic" = 1 ] && repo_key "$CHAOTIC_KEY" Chaotic-AUR

  # 2. keyring / mirrorlist packages, verified by pacman against the keys above
  if [ "$want_cachyos" = 1 ]; then
    local need=(cachyos-keyring cachyos-mirrorlist)
    case "$level" in
      znver4 | v4) need+=(cachyos-v4-mirrorlist) ;;
      v3) need+=(cachyos-v3-mirrorlist) ;;
    esac
    for n in "${need[@]}"; do
      pacman -Q "$n" >/dev/null 2>&1 && continue
      if url="$(cachyos_pkg_url "$n")"; then pkgs+=("$url"); else
        [ "$DRY" = 1 ] && pkgs+=("$CACHYOS_MIRROR/$n-<latest>-any.pkg.tar.zst") || die "cannot find $n in $CACHYOS_MIRROR"
      fi
    done
    # The x86_64_v3/v4 repos need CachyOS's patched pacman (what cachyos-repo.sh installs too).
    if [ "$level" != none ] && [ "$level" != plain ] && ! pacman -Qi pacman 2>/dev/null | grep -q '^Packager.*CachyOS'; then
      if url="$(cachyos_pkg_url pacman)"; then pkgs+=("$url"); else
        [ "$DRY" = 1 ] && pkgs+=("$CACHYOS_MIRROR/pacman-<latest>-x86_64.pkg.tar.zst") || die "cannot find pacman in $CACHYOS_MIRROR"
      fi
    fi
    if [ "${#pkgs[@]}" -gt 0 ]; then
      changed
      if [ "$DRY" = 1 ]; then echo "    [dry-run] sudo pacman -U ${pkgs[*]}"; else sudo pacman -U "${pkgs[@]}"; fi
    else
      echo "    ok      CachyOS keyring and mirrorlists installed"
    fi
  fi
  if [ "$want_chaotic" = 1 ]; then
    pkgs=()
    pacman -Q chaotic-keyring >/dev/null 2>&1 || pkgs+=("$CHAOTIC_MIRROR/chaotic-keyring.pkg.tar.zst")
    pacman -Q chaotic-mirrorlist >/dev/null 2>&1 || pkgs+=("$CHAOTIC_MIRROR/chaotic-mirrorlist.pkg.tar.zst")
    if [ "${#pkgs[@]}" -gt 0 ]; then
      changed
      if [ "$DRY" = 1 ]; then echo "    [dry-run] sudo pacman -U ${pkgs[*]}"; else sudo pacman -U "${pkgs[@]}"; fi
    else
      echo "    ok      Chaotic-AUR keyring and mirrorlist installed"
    fi
  fi

  # 3. pacman.conf (backup once, timestamped, before the first edit)
  local new want_ch=$want_chaotic
  new="$(mktmp)/pacman.conf"
  render_pacman_conf "$PACMAN_CONF" "$level" "$want_ch" >"$new"
  if cmp -s "$new" "$PACMAN_CONF"; then
    echo "    ok      $PACMAN_CONF needs no change"
    return 0
  fi
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] back up $PACMAN_CONF to $PACMAN_CONF.bak-dotfiles-$STAMP, then add:"
    diff -u "$PACMAN_CONF" "$new" | sed -n '/^+[^+]/p' | sed 's/^+/        + /' || true
    return 0
  fi
  sudo cp -p "$PACMAN_CONF" "$PACMAN_CONF.bak-dotfiles-$STAMP"
  echo "    backed up $PACMAN_CONF to $PACMAN_CONF.bak-dotfiles-$STAMP"
  sudo install -m644 "$new" "$PACMAN_CONF"
  echo "    updated $PACMAN_CONF (the packages stage runs the full -Syu)"
}

# ================================================================= stage: packages
enable_multilib() {
  local conf="$PACMAN_CONF" new
  if grep -q '^\[multilib\]' "$conf"; then
    echo "    ok      multilib already enabled"
    return 1
  fi
  new="$(mktmp)/pacman.conf"
  if grep -q '^#\[multilib\]' "$conf"; then
    awk '
      $0 == "#[multilib]" { print "[multilib]"; f = 1; next }
      f && /^#Include/ { sub(/^#/, ""); print; f = 0; next }
      { print }
    ' "$conf" >"$new"
  else
    { cat "$conf"; printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n'; } >"$new"
  fi
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] enable [multilib] in $conf (backup $conf.bak-dotfiles)"
    return 0
  fi
  [ -e "$conf.bak-dotfiles" ] || sudo cp "$conf" "$conf.bak-dotfiles"
  sudo install -m644 "$new" "$conf"
  echo "    enabled [multilib] in $conf"
  return 0
}

# gpu_ids: sets GPU_IDS to the PCI vendor id of every GPU (lspci -nn, else /sys/class/drm) and GPU_VM=1 when the
# GPU or the CPU says this is a virtual machine. Test hooks: lspci / systemd-detect-virt on PATH, SYS_DRM_GLOB.
gpu_ids() {
  local line v f
  GPU_IDS=()
  GPU_VM=0
  if command -v lspci >/dev/null 2>&1; then
    while IFS= read -r line; do
      v="$(grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]' <<<"$line" | tail -1 | tr -d '[]' | cut -d: -f1)"
      case "$line" in *QEMU* | *[Bb]ochs* | *[Vv]irtio*) v=1af4 ;; esac
      GPU_IDS+=("$v")
    done < <(lspci -nn | grep -E 'VGA compatible controller|3D controller|Display controller' || true)
  else
    for f in ${SYS_DRM_GLOB:-/sys/class/drm/card*/device/vendor}; do
      [ -r "$f" ] && GPU_IDS+=("$(sed 's/^0x//' "$f")")
    done
  fi
  for v in ${GPU_IDS[@]+"${GPU_IDS[@]}"}; do
    case "$v" in 1af4 | 1b36 | 1234 | 15ad | 80ee) GPU_VM=1 ;; esac
  done
  if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --vm -q 2>/dev/null; then GPU_VM=1; fi
}

# gpu_packages: fills GPU_PKGS and GPU_WHY (display text) from GPU_IDS: the full userspace stack per vendor, union for
# several GPUs. NVIDIA and unknown hardware get software Vulkan (swrast).
gpu_packages() {
  local v kinds=() k
  GPU_PKGS=(mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader)
  GPU_WHY=""
  if [ -n "${GPU_DRIVER:-}" ]; then
    kinds=("$GPU_DRIVER")
    GPU_WHY="GPU_DRIVER=$GPU_DRIVER"
  else
    for v in ${GPU_IDS[@]+"${GPU_IDS[@]}"}; do
      case "$v" in
        1002) k=radeon; GPU_WHY+="AMD GPU; " ;;
        8086) k=intel; GPU_WHY+="Intel GPU; " ;;
        1af4 | 1b36 | 1234) k=virtio; GPU_WHY+="QEMU/virtio GPU; " ;;
        10de) k=swrast; GPU_WHY+="NVIDIA GPU (not supported by this installer, software Vulkan); " ;;
        15ad | 80ee) k=swrast; GPU_WHY+="VMware/VirtualBox GPU; " ;;
        *) k=swrast; GPU_WHY+="unknown GPU $v; " ;;
      esac
      kinds+=("$k")
    done
    [ "${#kinds[@]}" -gt 0 ] || { kinds=(swrast); GPU_WHY="no GPU found (software Vulkan)"; }
  fi
  for k in $(printf '%s\n' "${kinds[@]}" | sort -u); do
    GPU_PKGS+=("vulkan-$k" "lib32-vulkan-$k")
    [ "$k" = intel ] && GPU_PKGS+=(intel-media-driver)
  done
  return 0
}

# cpu_ucode: prints the microcode package for this CPU (nothing inside a VM or for other vendors). Test hook: PROC_CPUINFO.
cpu_ucode() {
  [ "$GPU_VM" = 1 ] && return 0
  case "$(grep -m1 '^vendor_id' "${PROC_CPUINFO:-/proc/cpuinfo}" 2>/dev/null)" in
    *AuthenticAMD*) echo amd-ucode ;;
    *GenuineIntel*) echo intel-ucode ;;
  esac
}

# install_gpu_drivers: Mesa/Vulkan (+ lib32) for the detected GPU(s) and the CPU microcode, installed BEFORE the package
# lists so pacman never stops to ask which provider of vulkan-driver / lib32-vulkan-driver to use (and --noconfirm never
# silently picks nvidia-utils). GPU_DRIVER=radeon|intel|virtio|swrast|none overrides the detection.
install_gpu_drivers() {
  local pkgs uc
  case "${GPU_DRIVER:-}" in
    none) echo "    skip    GPU driver (GPU_DRIVER=none)"; return 0 ;;
    "" | radeon | intel | virtio | swrast) ;;
    *) die "GPU_DRIVER must be radeon, intel, virtio, swrast or none" ;;
  esac
  gpu_ids
  gpu_packages
  uc="$(cpu_ucode)"
  [ -z "$uc" ] || GPU_PKGS+=("$uc")
  pkgs=("${GPU_PKGS[@]}")
  echo "    GPU: ${GPU_WHY%; }"
  [ "$GPU_VM" = 1 ] && echo "    virtual machine: CPU microcode skipped"
  [ -z "$uc" ] || echo "    note: $uc updates the CPU at boot; regenerate the bootloader config if it does not pick it up (the installer does not touch it)"
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] sudo pacman -S ${PAC_FLAGS[*]} ${pkgs[*]}"
  elif [ -z "$(missing_pkgs "${pkgs[@]}")" ]; then
    echo "    ok      GPU driver (${pkgs[*]})"
  else
    changed
    sudo pacman -S "${PAC_FLAGS[@]}" "${pkgs[@]}"
  fi
}

# start_sudo_keepalive: ask for the password once, refresh the sudo timestamp until this script ends
# (long yay/makepkg builds outlast the default timeout). Stopped by the EXIT trap.
start_sudo_keepalive() {
  [ "$DRY" = 0 ] || return 0
  local s need=0
  for s in repos packages system; do stage_on "$s" && need=1; done
  [ "$need" = 1 ] || return 0
  sudo -v || die "sudo is needed"
  while true; do
    sudo -n true 2>/dev/null
    sleep 50
    kill -0 "$$" 2>/dev/null || exit 0
  done &
  KEEPALIVE_PID=$!
}

# missing_pkgs NAME...: names not satisfied by an installed package (pacman -T).
missing_pkgs() { pacman -T "$@" 2>/dev/null || true; }

stage_packages() {
  log "Stage packages"
  enable_multilib || true

  # Full upgrade, never a bare -Sy (partial upgrades break Arch). Also refreshes the new multilib db.
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] sudo pacman -Syu ${PAC_FLAGS[*]} base-devel git pciutils"
  else
    sudo pacman -Syu "${PAC_FLAGS[@]}" base-devel git pciutils
  fi

  install_gpu_drivers

  if ! command -v yay >/dev/null 2>&1; then
    changed
    if [ "$DRY" = 1 ]; then
      echo "    [dry-run] install yay (repo package if available, else AUR build)"
    elif pacman -Si yay >/dev/null 2>&1; then
      sudo pacman -S "${PAC_FLAGS[@]}" yay
    else
      local d
      d="$(mktmp)"
      git clone https://aur.archlinux.org/yay.git "$d/yay"
      (cd "$d/yay" && if [ -t 0 ] && [ "$YES" = 0 ]; then makepkg -si; else makepkg -si --noconfirm; fi)
    fi
  else
    echo "    ok      yay"
  fi

  local pac aur missing
  mapfile -t pac < <(read_list "$PKG_DIR/pacman.txt")
  mapfile -t aur < <(read_list "$PKG_DIR/aur.txt")

  missing="$(missing_pkgs "${pac[@]}")"
  if [ -z "$missing" ]; then
    echo "    ok      pacman.txt (${#pac[@]} packages installed)"
  else
    changed
    FONTS_DIRTY=1
    # shellcheck disable=SC2086
    if [ "$DRY" = 1 ]; then
      echo "    [dry-run] sudo pacman -S ${PAC_FLAGS[*]} $(echo $missing)"
    else
      # shellcheck disable=SC2086
      sudo pacman -S "${PAC_FLAGS[@]}" $missing
    fi
  fi

  missing="$(missing_pkgs "${aur[@]}")"
  if [ -z "$missing" ]; then
    echo "    ok      aur.txt (${#aur[@]} packages installed)"
  else
    changed
    FONTS_DIRTY=1
    if [ "$DRY" = 1 ]; then
      # shellcheck disable=SC2086
      echo "    [dry-run] yay -S ${PAC_FLAGS[*]} $(echo $missing)"
    else
      # shellcheck disable=SC2086
      yay -S "${PAC_FLAGS[@]}" $missing
    fi
  fi

  install_bundles
  flatpak_apps
}

# install_bundles: packages/optional/NAME.txt for each --with bundle. Names may be repo or AUR, so yay handles all.
install_bundles() {
  local b names missing
  for b in $(printf '%s\n' ${BUNDLES[@]+"${BUNDLES[@]}"} | sort -u); do
    mapfile -t names < <(read_list "$PKG_DIR/optional/$b.txt")
    missing="$(missing_pkgs "${names[@]}")"
    if [ -z "$missing" ]; then
      echo "    ok      optional/$b.txt (${#names[@]} packages installed)"
    else
      changed
      FONTS_DIRTY=1
      if [ "$DRY" = 1 ]; then
        # shellcheck disable=SC2086
        echo "    [dry-run] yay -S ${PAC_FLAGS[*]} $(echo $missing)   (bundle $b)"
      else
        # shellcheck disable=SC2086
        yay -S "${PAC_FLAGS[@]}" $missing
      fi
    fi
  done
}

flatpak_apps() {
  local apps app
  mapfile -t apps < <(read_list "$PKG_DIR/flatpak.txt")
  if ! command -v flatpak >/dev/null 2>&1; then
    if [ "$DRY" = 1 ]; then
      echo "    [dry-run] flatpak not installed yet; would add flathub (user) and install: ${apps[*]}"
    else
      warn "flatpak not found, skipping flatpak apps"
    fi
    return 0
  fi
  if [ "$DRY" = 1 ] && [ ! -d "$HOME/.local/share/flatpak" ]; then
    # querying would create ~/.local/share/flatpak; nothing is set up there yet
    echo "    [dry-run] add flathub (user) and install: ${apps[*]}"
    changed
    return 0
  fi
  if ! flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub; then
    run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  else
    echo "    ok      flathub remote"
  fi
  for app in "${apps[@]}"; do
    if flatpak info "$app" >/dev/null 2>&1; then
      echo "    ok      flatpak $app"
    else
      run flatpak install --user -y flathub "$app"
    fi
  done
}

# ================================================================= stage: links
create_brave_webapp() {
  local name="$1" url="$2" icon="${3:-brave}" file
  file="$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]_')"
  write_file "$HOME/.local/share/applications/webapp_${file}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=$name
Exec=brave --app="$url"
Terminal=false
Type=Application
Categories=Network;WebBrowser;
Icon=$icon
StartupNotify=true
EOF
}

gsettings_set() { # SCHEMA KEY VALUE: only when it differs; failures never abort the install
  local cur
  cur="$(gsettings get "$1" "$2" 2>/dev/null)" || { warn "gsettings: cannot read $1 $2"; return 0; }
  if [ "$cur" = "$3" ] || [ "$cur" = "'$3'" ]; then
    echo "    ok      gsettings $2"
    return 0
  fi
  changed
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] gsettings set $1 $2 $3"
  else
    gsettings set "$1" "$2" "$3" 2>/dev/null || warn "gsettings set $1 $2 failed (no dbus/dconf session?)"
  fi
}

stage_links() {
  log "Stage links"
  [ "$DRY" = 1 ] || mkdir -p "$HOME/.config"

  # The repo is public: enable the privacy pre-commit hook (.githooks/pre-commit) for this clone
  local hp
  hp="$(git -C "$DOTFILES_DIR" config --get core.hooksPath 2>/dev/null || true)"
  if [ "$hp" = .githooks ]; then
    echo "    ok      git core.hooksPath"
  elif git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    run git -C "$DOTFILES_DIR" config core.hooksPath .githooks
  fi

  log "Config directories"
  local app
  for app in hypr nvim kitty zellij theme quickshell opencode wivrn alacritty ghostty fastfetch; do
    link "$CONFIG_DIR/$app" "$HOME/.config/$app"
  done
  link "$CONFIG_DIR/brave-flags.conf" "$HOME/.config/brave-flags.conf"

  log "Shell dotfiles"
  link "$CONFIG_DIR/shell/zshrc" "$HOME/.zshrc"
  link "$CONFIG_DIR/shell/bashrc" "$HOME/.bashrc"
  link "$CONFIG_DIR/shell/bash_profile" "$HOME/.bash_profile"
  link "$CONFIG_DIR/shell/inputrc" "$HOME/.inputrc"
  # Starship: default prompt settings, only seeded (edit ~/.config/starship.toml freely afterwards)
  printf 'add_newline = true\n' | seed_file "$HOME/.config/starship.toml" || true
  if ! skipped omz; then
    if [ -d "$HOME/.oh-my-zsh" ]; then
      echo "    ok      oh-my-zsh"
    else
      run git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    fi
  fi

  log "Zellij claude-tabs plugin"
  # Standalone package in its own repo (default checkout below). Its setup.sh links the plugin into
  # ~/.config/zellij/plugins, installs the WC3 icon font, pre-grants permissions and adds the Claude Code hooks.
  local ct="${CLAUDE_TABS_DIR:-$HOME/code/crossatko/zellij-wc3cz-claude}"
  if skipped claude-tabs; then
    echo "    skipped (INSTALL_SKIP)"
  elif [ -f "$ct/setup.sh" ]; then
    if [ "$DRY" = 1 ]; then
      echo "    [dry-run] sh $ct/setup.sh"
    else
      sh "$ct/setup.sh" || warn "claude-tabs setup failed (use default_layout 'compact' as a fallback)"
      FONTS_DIRTY=1
    fi
  else
    info "claude-tabs checkout not found at $ct: clone it and run its setup.sh, or set default_layout 'compact' in config/zellij/config.kdl"
  fi

  log "Scripts, launcher, portals, units"
  local s
  for s in "$CONFIG_DIR"/nautilus/scripts/*; do
    [ -e "$s" ] && link "$s" "$HOME/.local/share/nautilus/scripts/$(basename "$s")"
  done
  # Only the commands dir: ~/.config/launcher also holds the user's config.json.
  link "$CONFIG_DIR/launcher/commands" "$HOME/.config/launcher/commands"
  # Portal routing (screen sharing pinned to hyprland, file dialogs -> Nautilus chooser) and the GNOME portal unit
  # override: Hyprland never activates graphical-session.target, which the packaged unit requires.
  link "$CONFIG_DIR/xdg-desktop-portal/portals.conf" "$HOME/.config/xdg-desktop-portal/portals.conf"
  link "$CONFIG_DIR/systemd/user/xdg-desktop-portal-gnome.service" "$HOME/.config/systemd/user/xdg-desktop-portal-gnome.service"
  link "$CONFIG_DIR/systemd/user/librepods.service" "$HOME/.config/systemd/user/librepods.service"
  # Launcher shim: applies the wallpaper theme to Brave's profile just before it starts
  link "$CONFIG_DIR/theme/bin/brave" "$HOME/.local/bin/brave"
  link "$CONFIG_DIR/launcher/jellyfin/bin/jellyfin-qs" "$HOME/.local/bin/jellyfin-qs"

  # Link router (config/url-router): http(s) links opened by native apps go to the Figma app (figma.com files),
  # the matching Brave web app window, everything else to Brave. Roll back with:
  #   xdg-mime default brave-browser.desktop x-scheme-handler/http x-scheme-handler/https
  # Exec stays unquoted: xdg-open's own desktop-file parser does not strip quotes (so no spaces in $HOME).
  link "$CONFIG_DIR/url-router/bin/url-router" "$HOME/.local/bin/url-router"
  sed "s|@ROUTER@|$HOME/.local/bin/url-router|" "$CONFIG_DIR/url-router/url-router.desktop.in" |
    write_file "$HOME/.local/share/applications/url-router.desktop"
  if command -v xdg-mime >/dev/null 2>&1; then
    if [ "$(xdg-mime query default x-scheme-handler/http 2>/dev/null)" = url-router.desktop ] &&
      [ "$(xdg-mime query default x-scheme-handler/https 2>/dev/null)" = url-router.desktop ]; then
      echo "    ok      xdg-mime http(s) -> url-router"
    else
      run xdg-mime default url-router.desktop x-scheme-handler/http x-scheme-handler/https
    fi
  fi

  log "Firefox translucent header"
  local ffdir="$HOME/.config/mozilla/firefox" ffp
  if [ -f "$ffdir/profiles.ini" ]; then
    ffp="$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$ffdir/profiles.ini")"
    if [ -n "$ffp" ] && [ -d "$ffdir/$ffp" ]; then
      link "$CONFIG_DIR/firefox/userChrome.css" "$ffdir/$ffp/chrome/userChrome.css"
      link "$CONFIG_DIR/firefox/user.js" "$ffdir/$ffp/user.js"
    fi
  else
    echo "    (no Firefox profile yet; re-run --only links after the first Firefox start)"
  fi

  log "Theme (config/theme/README.md)"
  if [ "$DRY" = 1 ]; then
    echo "    [dry-run] theme-seed; theme.py render if out/palette.json is still missing"
  else
    # theme-seed is a no-op on a machine with a render or a selection; render only when nothing exists yet.
    sh "$CONFIG_DIR/theme/bin/theme-seed" -q || true
    local out="${THEME_OUT_DIR:-$CONFIG_DIR/theme/out}"
    if [ ! -f "$out/palette.json" ]; then
      if python3 -I "$CONFIG_DIR/theme/theme.py" render; then changed; else warn "theme render failed"; fi
    else
      echo "    ok      theme out/"
    fi
  fi

  log "GTK / dark mode seed"
  # settings.ini, gtkrc and gsettings are only seeded on the first run: afterwards the theme engine (theme.py)
  # owns them and rewriting would undo the wallpaper theme.
  local gtk_seeded=0 ini
  ini='[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Oxygen_White
gtk-application-prefer-dark-theme=1'
  if printf '%s\n' "$ini" | seed_file "$HOME/.config/gtk-3.0/settings.ini"; then gtk_seeded=1; fi
  printf '%s\n' "$ini" | seed_file "$HOME/.config/gtk-4.0/settings.ini" || true
  printf 'gtk-theme-name="Adwaita-dark"\ngtk-icon-theme-name="Adwaita"\ngtk-cursor-theme-name="Oxygen_White"\n' |
    seed_file "$HOME/.gtkrc-2.0" || true
  # X11 / legacy fallback for the cursor theme (directory name, not the display name "Oxygen White").
  # Hyprland itself gets it from env.lua (XCURSOR_THEME) and autostart.lua (hyprctl setcursor).
  printf '[Icon Theme]\nName=Default\nComment=Default Cursor Theme\nInherits=Oxygen_White\n' |
    seed_file "$HOME/.local/share/icons/default/index.theme" || true
  printf 'file://%s/Documents\nfile://%s/Downloads\nfile://%s/Music\nfile://%s/Pictures\nfile://%s/Videos\nfile://%s/code\n' \
    "$HOME" "$HOME" "$HOME" "$HOME" "$HOME" "$HOME" | seed_file "$HOME/.config/gtk-3.0/bookmarks" || true

  if command -v gsettings >/dev/null 2>&1; then
    if [ "$gtk_seeded" = 1 ]; then
      gsettings_set org.gnome.desktop.interface color-scheme prefer-dark
      gsettings_set org.gnome.desktop.interface gtk-theme Adwaita-dark
      gsettings_set org.gnome.desktop.interface icon-theme Adwaita
      gsettings_set org.gnome.desktop.interface cursor-theme Oxygen_White
    fi
    # blueman's own connect/disconnect notifier is off: the shell's BtNotifier posts those
    gsettings_set org.blueman.general plugin-list "['!ConnectionNotifier']"
  else
    warn "gsettings not found; skipping dark-mode gsettings"
  fi

  local d
  for d in Documents Downloads Music Pictures Videos code; do
    [ -d "$HOME/$d" ] || run mkdir -p "$HOME/$d"
  done

  log "Brave web apps"
  local before_apps=$CHANGES
  create_brave_webapp "Figma" "https://www.figma.com"
  create_brave_webapp "Linear" "https://linear.app"
  if [ "$CHANGES" -gt "$before_apps" ] && command -v update-desktop-database >/dev/null 2>&1 && [ "$DRY" = 0 ]; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  fi

  log "AirPods daemon (config/librepods/README.md)"
  if skipped librepods; then
    echo "    skipped (INSTALL_SKIP)"
  elif [ "$DRY" = 1 ]; then
    echo "    [dry-run] bash config/librepods/build.sh"
  else
    bash "$CONFIG_DIR/librepods/build.sh" || warn "librepods build failed (AirPods section stays off until it works)"
  fi

  if [ "$FONTS_DIRTY" = 1 ] && [ "$DRY" = 0 ] && command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f >/dev/null 2>&1 || true
  fi

  if [ "$CHSH" = 1 ]; then
    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [ -z "$zsh_path" ]; then
      warn "--chsh: zsh not installed yet (run the packages stage first)"
    elif [ "$(getent passwd "$USER" | cut -d: -f7)" = "$zsh_path" ]; then
      echo "    ok      login shell is already zsh"
    else
      run chsh -s "$zsh_path"
    fi
  fi
}

# ================================================================= stage: system
host_var() {
  local raw
  raw="$(cat /etc/hostname 2>/dev/null || uname -n)"
  raw="$(printf '%s' "$raw" | tr -d '\n')"
  # CrossBattlestation -> HOST_CROSS_BATTLESTATION (read by hypridle.conf `# hyprlang if`). The Hyprland Lua
  # config matches the hostname itself (host.lua: BATTLESTATION, WORKSTATION, ARCHLINUX, anything ending in VM).
  printf 'HOST_%s' "$(printf '%s' "$raw" | sed -e 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' -e 's/-/_/g' | tr '[:lower:]' '[:upper:]')"
}

sync_etc_environment() {
  local var="$1" cur new
  cur="$(mktmp)/environment.cur"
  new="$(mktmp)/environment.new"
  cat /etc/environment >"$cur" 2>/dev/null || : >"$cur"
  # Managed line: HOST_* only. Everything else in the file stays as it is.
  awk -v line="$var=1" '
    /^HOST_/ { if (!done) { print line; done = 1 } next }
    { print }
    END { if (!done) print line }
  ' "$cur" >"$new"
  sudo_install "$new" /etc/environment || return 0
  return 0
}

enable_unit() {
  local unit="$1"
  if [ "$DRY" = 1 ]; then
    if systemctl is-enabled "$unit" >/dev/null 2>&1; then echo "    ok      $unit enabled"; else
      changed
      echo "    [dry-run] sudo systemctl enable --now $unit"
    fi
  elif systemctl is-enabled "$unit" >/dev/null 2>&1 && systemctl is-active "$unit" >/dev/null 2>&1; then
    echo "    ok      $unit"
  else
    changed
    sudo systemctl enable --now "$unit"
  fi
}

stage_system() {
  log "Stage system (sudo)"
  local udev_changed=0 units_changed=0 f dest tmp

  for f in 50-vial 61-corne-nojoystick 62-corne-via; do
    sudo_install "$SYS_DIR/udev/rules.d/$f.rules" "/etc/udev/rules.d/$f.rules" && udev_changed=1
  done
  sudo_install "$SYS_DIR/systemd/logind.conf.d/inhibit-delay.conf" /etc/systemd/logind.conf.d/inhibit-delay.conf && units_changed=1

  # tty1 autologin: the file names one user, replaced with the current one
  tmp="$(mktmp)/autologin.conf"
  sed "s|--autologin [^ ]*|--autologin $USER|" "$SYS_DIR/systemd/system/getty@tty1.service.d/autologin.conf" >"$tmp"
  sudo_install "$tmp" "/etc/systemd/system/getty@tty1.service.d/autologin.conf" && units_changed=1

  local mt=0
  if command -v mullvad >/dev/null 2>&1 && command -v tailscale >/dev/null 2>&1; then
    sudo_install "$SYS_DIR/mullvad-tailscale/coexist.nft" /etc/mullvad-tailscale/coexist.nft && units_changed=1
    sudo_install "$SYS_DIR/systemd/system/mullvad-tailscale.service" /etc/systemd/system/mullvad-tailscale.service && units_changed=1
    mt=1
  else
    echo "    (mullvad + tailscale not both installed: skipping mullvad-tailscale coexistence files)"
  fi

  if [ "$udev_changed" = 1 ]; then
    if [ "$DRY" = 1 ]; then echo "    [dry-run] sudo udevadm control --reload-rules && trigger"; else
      sudo udevadm control --reload-rules && sudo udevadm trigger
    fi
  fi
  if [ "$units_changed" = 1 ]; then
    if [ "$DRY" = 1 ]; then echo "    [dry-run] sudo systemctl daemon-reload"; else sudo systemctl daemon-reload; fi
  fi

  local hv
  hv="$(host_var)"
  log "Host marker $hv in /etc/environment"
  sync_etc_environment "$hv"

  log "Services"
  local u
  for u in bluetooth NetworkManager tailscaled docker ufw; do
    systemctl list-unit-files "$u.service" 2>/dev/null | grep -q "^$u.service" || { echo "    (skip $u: not installed)"; continue; }
    enable_unit "$u"
  done
  [ "$mt" = 1 ] && enable_unit mullvad-tailscale
  if systemctl list-unit-files mullvad-daemon.service 2>/dev/null | grep -q '^mullvad-daemon.service'; then
    enable_unit mullvad-daemon
  fi

  log "Firewall (ufw)"
  if command -v ufw >/dev/null 2>&1; then
    local st=""
    [ "$DRY" = 1 ] || st="$(sudo ufw status verbose 2>/dev/null || true)"
    if [ "$DRY" = 0 ] && grep -q '^Status: active' <<<"$st" && grep -q 'Default: deny (incoming), allow (outgoing)' <<<"$st"; then
      echo "    ok      ufw active, deny incoming / allow outgoing"
    else
      changed
      if [ "$DRY" = 1 ]; then
        echo "    [dry-run] sudo ufw default deny incoming; default allow outgoing; --force enable (skipped if already so)"
      else
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw --force enable
      fi
    fi
  else
    echo "    (ufw not installed)"
  fi

  log "Docker group"
  if ! getent group docker >/dev/null 2>&1; then
    echo "    (no docker group yet; install docker first)"
  elif id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    echo "    ok      $USER is in docker"
  else
    run sudo usermod -aG docker "$USER"
  fi
}

# ================================================================= main
[ "$DRY" = 1 ] && log "Dry run: nothing is changed, sudo is not called"
start_sudo_keepalive
stage_on repos && stage_repos
stage_on packages && stage_packages
stage_on links && stage_links
stage_on system && stage_system

echo
if [ -n "$(bundle_names)" ]; then
  echo "Optional bundles available: $(bundle_names | paste -sd' ' -); install with --with NAME (or --with all)."
  echo
fi
if [ "$DRY" = 1 ]; then
  echo "Dry run finished: $CHANGES change(s) would be made."
else
  echo "Done: $CHANGES change(s) made."
fi

if stage_on links || stage_on packages || stage_on repos; then
  cat <<'EOF'

Manual steps (not automated):
  - Hyprland fork (glass compositing; battlestation only): build/install from the fork repo. Stock `hyprland` works elsewhere.
  - Font Awesome 7 Pro (licensed) into ~/.local/share/fonts/FontAwesomePro/, and the Paper Mono font into ~/.local/share/fonts/.
  - zellij claude-tabs: clone its repo to ~/code/crossatko/zellij-wc3cz-claude (or set CLAUDE_TABS_DIR), then re-run `--only links`.
  - Sign in: 1Password, Mullvad, `sudo tailscale up`, `jellyfin-qs login`, Brave/Firefox profiles.
  - Optional privacy deny-list for the pre-commit hook: ~/.config/dotfiles-private/denylist.
  - Machine-specific hardware setup beyond the GPU stack and CPU microcode (bootloader config, NVIDIA).
  - Log out and back in after the first run (docker group, environment, themes).
  - Optional third-party repos (CachyOS, Chaotic-AUR; not needed by the package lists): `./install.sh --repos`.
  - Root-owned files and services: `./install.sh --system` (or `--only system`); change the login shell with `--chsh`.
  - macOS is maintained by hand.
EOF
fi

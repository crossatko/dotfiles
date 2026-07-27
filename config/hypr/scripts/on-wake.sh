#!/bin/bash
# Reconciles display brightness + TV input after waking from sleep.
#
# This used to independently re-implement the dim/restore decision here
# (pgrep for gamescope, then blindly ddcutil-dim or restore) -- that was
# wrong: it dimmed monitors just because a gamescope process existed
# *anywhere*, without checking whether the TV was actually the active
# session, and a sleep/wake cycle can silently drift real hardware state out
# from under steam-tv-dim.lua's `dimmed` flag. That combination once dimmed
# both non-TV monitors to near-black while the TV wasn't even in use and
# never recovered, forcing a hard reboot.
#
# steam-tv-dim.lua already has the correct, single-source-of-truth decision
# (tv-connected AND big-picture-active), so just force it to recompute here
# instead of duplicating it.
hyprctl eval 'hypr_tv_dim_force_resync()' >/dev/null 2>&1

#!/bin/sh

# hernia: The highly opinionated wannabe-love-child of FAI, Ansible & Heroku
#
# © Copyright 2014-2016 Rowan Thorpe
# Any contributions noted in the AUTHORS file.
#
# This file is part of hernia.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# emacs ==> -*- mode: sh; eval: (auto-complete-mode 1); -*-

# * This requires $libfile, $deployfile, $runfile, $varsfile, $pkgssubdir as
#   commandline args (pointing to usable files). If you wish to run it
#   independently from the git-hook, create the files manually and run this with
#   those names as args.

set -e

# Should probably always be set to 1, but edit it if you want.
debug=1

libfile="$1"
deployfile="$2"
runfile="$3"
varsfile="$4"
pkgssubdir="$5"
this="$6"
shift 6

scriptpath="$(readlink -e "$0")" && \
    scriptdir="$(dirname "$scriptpath")" && \
    test -s "$libfile" && \
    . "$libfile" || \
        { printf 'Failed using readlink or dirname, or sourcing lib file "%s"\n' "$libfile" >&2; exit 1; }
scriptname='run' # override $(basename "$0" .sh) here, this may be running from a tempfile
info 'Sourced lib file "%s"\n' "$libfile"

source_vars '/root/external_vars.sh' 'debug_global|default_password' || \
    die 'Failed sourcing external_vars file /root/external_vars.sh\n'
info 'Sourced external_vars file /root/external_vars.sh\n'

source_vars "$varsfile" 'daemon_name|ulimit_s_val|daemon_opts|post_run_cmds' || \
    die 'Failed sourcing vars file "%s"\n' "$varsfile"
info 'Sourced vars file "%s"\n' "$varsfile"

run_dir="/var/run/$daemon_name"
log_dir="/var/log/$daemon_name"

if ! test -d "$run_dir"; then
    mkdir "$run_dir" || \
        die 'Failed creating rundir "%s"\n' "$run_dir"
    info 'Created rundir "%s"\n' "$run_dir"
fi

chown -R "${daemon_name}:$daemon_name" "$run_dir" "$log_dir" || \
    die 'Failed chowning rundir to user "%s" and group "%s"\n' "$daemon_name" "$daemon_name"
info 'Chowned run_dir to user "%s" and group "%s"\n' "$daemon_name" "$daemon_name"

chmod -R ug=rwX,o= "$run_dir" "$log_dir" || \
    die 'Failed chmodding run_dir to ug=rwX,o=\n'
info 'Chmodded run_dir to ug=rwX,o=\n'

cd "$log_dir" || \
    die 'Failed entering directory "%s"\n' "$log_dir"
info 'Entered directory "%s"\n' "$log_dir"

if test -n "$ulimit_s_val"; then
    ulimit -s "$ulimit_s_val" || \
        die 'Failed doing "ulimit -s %s"\n' "$ulimit_s_val"
    info 'Did "ulimit -s %s"\n' "$ulimit_s_val"
fi

"$daemon_name" $daemon_opts "$@" </dev/null >&2 &
test 0 -eq $? || \
    die 'Failed launching "%s%s%s"\n' "$daemon_name" "${daemon_opts:+ }$daemon_opts" "${*:+ }$*"
info 'Launched "%s%s%s"\n' "$daemon_name" "${daemon_opts:+ }$daemon_opts" "${*:+ }$*"

if test -n "$post_run_cmds"; then
    info 'Waiting 4 second before post-run commands\n'
    sleep 4
    eval "$post_run_cmds" || \
        die 'Failed running post-run commands\n'
    info 'Ran post-run commands\n'
fi
info 'Waiting for background process to terminate if it hasn'\''t already\n'
wait

info 'Run finished\n'

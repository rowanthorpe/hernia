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

# This locks the shell interpreter (and its libs) and the external_vars.sh file (in
# the repo locally, and in the root-dir on the server) into memory so passwords are
# never swapped to disk.
memlockd_add_files() {
    exit_trap="$exit_trap"'
        if test 0 -eq $(id -u); then
            rm -f /etc/memlockd.d/hernia-temp.cfg && \
                 service memlockd restart
        else
            sudo -n rm -f /etc/memlock.d/hernia-temp.cfg && \
                 sudo -n service memlockd restart
        fi
'
    trap "$exit_trap" EXIT
    if ! test -e /etc/memlockd.d/hernia-temp.cfg; then
        {
            printf '+'; readlink -e "$(sed -rne '1 s/^#!([^ \t]+)([ \t].*)?$/\1/; p; q' "$scriptpath")"
            case "$scriptname" in
                provision)
                    printf '%s\n' "$(readlink -e "${scriptdir}/..")/external_vars.sh"
                    ;;
                *)
                    printf '/root/external_vars.sh\n'
                    ;;
            esac
        } | sudo -n tee /etc/memlockd.d/hernia-temp.cfg >/dev/null 2>&1 && \
            sudo -n service memlockd restart
    fi
}

warn() { printf ''"$@" | sed -e "s/^/${scriptname}: /" >&2; }

info() { ! test 1 = "$debug" && ! test 1 = "$debug_global" || warn "$@"; }

die() { warn "$@"; exit 1; }

die_u() { usage >&2; die "$@"; }

vdiff() {
    _diff_content="$(diff -Nur "$1" "$2" || :)"
    if test -z "$_diff_content"; then
        printf '*** identical directories\n'
    else
        printf '%s\n' "$_diff_content"
    fi
    info 'Diffed "%s" against "%s"\n' "$1" "$2"
}

explain_dir_structure() {
    _die_text='Ensure the following dir-structure is in place first for the deployment to work (to start off create dirs with fake "early" $timestamp like "0"):
'
    for _src_dest in $dirs; do
        _dest=$(printf '%s\n' "$_src_dest" | cut -d: -f2-)
        _die_text="$_die_text
  $_dest
    (symlink to) -> ${_dest}.\${timestamp}
"
    done
    printf '%s\n' "$_die_text"
}

get_vars() {
    {
        cat "$1" 2>/dev/null || sudo -n cat "$1"
    } | \
        grep -E "^(${2:-debug_global|default_password|default_provider_password|services_password|repo|branch|email|whitelist_addresses|bare_domain|server_aliases|main_alias|ns_1|public_ipv4_address|debug|repo_pub_key_url|apt_source_line_1|apt_source_line_2|apt_source_filename|packages_manual|packages_auto|packages_prevent_service_autostart|services_post_install|services_post_deploy|replace_hash|perms_hash|add_content_hash|new_content_hash|patch_content_hash|post_deploy_cmds|past_timestamped_dirs_to_keep|run_after_deploy|ulimit_s_val|post_run_cmds|daemon_name|daemon_opts})="
}

source_vars() {
    eval "$(get_vars "$@")"
}

prompt() {
    _private=0
    _default=''
    _allow_empty=0
    while test 0 -ne $#; do
        case "$1" in
            -z)
                _allow_empty=1
                shift
                ;;
            -p)
                _private=1
                shift
                ;;
            -d)
                _default="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done
    _varname="$1"
    shift
    while : ; do
        if test -n "$1"; then
            printf '%s (%s):' "$_varname" "$1"
        else
            printf '%s:' "$_varname"
        fi
        test 0 -eq $_allow_empty && test -z "$_default" || \
            printf 'default=%s:' "${_default:-\"\"}"
        printf ' '
        test 0 -eq $_private || stty -echo
        eval 'IFS= read -r $_varname'
        if test 1 -eq $_private; then
            printf '\n'
            stty echo
        fi
        eval '
            if test -z "$'$_varname'"; then
                if test -n "$_default"; then
                    '$_varname'="$_default"
                elif test 0 -eq $_allow_empty; then
                    printf "Empty field entered but no default available\\n" >&2
                    continue
                fi
            fi
        '
        break
    done
}

quote_p() { sed -e "s/'/'\\\\''/g"; }

quote() { printf '%s' "$1" | quote_esc_p; }

quote_wrap_p() { printf "'"; quote_p; printf "'"; }

quote_wrap() { printf '%s' "$1" | quote_wrap_p; }

# Show from list "a" if matches from list "b" (or matches prefix up to "c" string
# if specified). Negate meaning with "-n" as optarg.
a_if_in_b() {
    if test '-n' = "$1"; then
        _not=1
        shift
    else
        _not=0
    fi
    _list_a="$1"
    _list_b="$2"
    _delimiter="$3"
    printf '%s\n' "$_list_a" | \
        tr ' ' '\n' | \
        grep `test 0 -eq $_not || printf -- -v` -E "^($(printf '%s\n' "$_list_b" | sed -e 's/ +/|/'))${_delimiter:-\$}" | \
        tr '\n' ' ' | \
        sed -e 's/ $//'
}

mergedirs() {
    _md_retval=0
    _dest="$1"
    shift
    yes | \
        for _src do
            cp -R --no-dereference --preserve=all --force --one-file-system \
                  --no-target-directory --reflink=auto "${_src}/" "$_dest" || { _md_retval=1; break; }
        done 2>/dev/null
    return $_md_retval
}

iterate_pieces() {
    _num_pieces="$1"
    _code="$2"
    shift 2
    _alphabet="$(printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\np\nq\nr\ns\nt\nu\nv\nw\nx\ny\nz\n')"
    for _chunk do
        _counter=1
        while test $_counter -lt $_num_pieces; do
            _varname=$(printf '%s\n' "$_alphabet" | head -n $_counter | tail -n 1)
            eval "_$_varname"'=$(printf %s\\n "$_chunk" | cut -d: -f$_counter)'
            _counter=$(expr $_counter + 1)
        done
        _varname=$(printf '%s\n' "$_alphabet" | head -n $_counter | tail -n 1)
        eval "_$_varname"'=$(printf %s\\n "$_chunk" | cut -d: -f${_counter}-)'
        eval "$_code" || return $?
    done
}

secure_sed() {
    # sed commands are all in first line of stdin, not as args, so won't be exposed by ps.
    # This will always be on the receiving end of a pipe, so will always be in a subshell, so
    # don't extend $exit_trap here because that will run all its commands when exiting this
    # subshell rather than the main shell [wrong].
    IFS= read -r _sedcmds
    trap 'test -z "$_tmpfifo" || ! test -e "$_tmpfifo" || rm -f "$_tmpfifo"' EXIT
    _tmpfifo="$(mktemp -u)" && \
        mkfifo -m 0600 "$_tmpfifo" && \
        find -- "$@" -type f -print0 | \
            xargs -0 -n 1 -I {} sh -c '
                sed -f '"$_tmpfifo"' --follow-symlinks -i -- {} &
                printf %s\\n '\'"$_sedcmds"\'' >'\'"$_tmpfifo"\'' && \
                    wait || exit 255
            '
}

_ssh_scp_opts() { # action, opts, args, address
    _action="$1"
    shift
    _sudo=0
    _use_password=0
    _title=''
    _strict_host=1
    _read_stdin=0
    while test 0 -ne $#; do
        case "$1" in
            -p)
                _use_password=1
                shift
                ;;
            -h)
                _strict_host=0
                shift
                ;;
            -t)
                _title="$2"
                shift 2
                ;;
            -s)
                ! test 'ssh' = "$_action" || _sudo=1
                shift
                ;;
            -N)
                ! test 'ssh' = "$_action" || _read_stdin=1
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    if test 1 -eq $_use_password; then
        _sshopts='-o PubkeyAuthentication=no -o PasswordAuthentication=yes'
    else
        _sshopts='-o PubkeyAuthentication=yes -o PasswordAuthentication=no'
    fi
    if test 1 -eq $_strict_host; then
        _sshopts="$_sshopts -o StrictHostKeyChecking=yes"
    else
        _sshopts="$_sshopts -o StrictHostKeyChecking=no"
    fi
    # Set extra ssh options to reduce the chance of fail2ban bouncing us
    _sshopts="$_sshopts -o ControlMaster=auto -o ControlPath=~/.ssh/control:%C -o ControlPersist=3 -o ConnectTimeout=15"
    ! test 'ssh' = "$_action" || _sshopts="$_sshopts -T"
    case "$_action" in
        scp)
            _args="$(quote_wrap "$1") $(quote_wrap "$2")" # only 1 "from" and 1 "to" arg for now
            shift 2
            ;;
        ssh)
            _cmdline="$1"
            shift
            _address=$(quote_wrap "$1")
            shift
            _args="sh -c $(quote_wrap "set -e; DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND; DEBCONF_NONINTERACTIVE_SEEN=true; export DEBCONF_NONINTERACTIVE_SEEN; $_cmdline")"
            test 0 -eq $_sudo || _args="sudo -n $_args"
            _args=$(quote_wrap "$_args")
            test 1 -eq $_read_stdin || _sshopts="$_sshopts -n"
            ;;
    esac
}

_get_retval() {
    _retval=$?
    if test -n "$_title"; then
        if test 0 -eq $_retval; then
            info 'Succeeded "%s"\n' "$_title"
        else
            info 'Failed "%s"\n' "$_title"
        fi
    fi
    return $_retval
}

do_scp() {
    _ssh_scp_opts 'scp' "$@"
    info 'doing: %s %s -- %s\n' "$_action" "$_sshopts" "$_args"
    eval "$_action -r $_sshopts -- $_args"
    _get_retval
}

do_scp_s() {
    _user="$1"
    _direction="$2"
    _a="$3"
    _b="$4"
    shift 4
    if test 'in' = "$_direction"; then
        do_scp "$@" "${_user}@${SERVER_DOMAIN}:$_a" "$_b"
    elif test 'out' = "$_direction"; then
        do_scp "$@" "$_a" "${_user}@${SERVER_DOMAIN}:$_b"
    fi
}

do_scp_r() {
    do_scp_s 'root' "$@"
}

do_scp_u() {
    do_scp_s "$USER_NAME" "$@"
}

do_ssh() {
    _ssh_scp_opts 'ssh' "$@"
    info 'doing: %s %s -- %s %s\n' "$_action" "$_sshopts" "$_address" "$_args"
    eval "$_action $_sshopts -- $_address $_args"
    _get_retval
}

do_ssh_s() {
    _user="$1"
    shift
    do_ssh "$@" "${_user}@$SERVER_DOMAIN"
}

do_ssh_r() {
    do_ssh_s 'root' "$@"
}

do_ssh_u() {
    do_ssh_s "$USER_NAME" "$@"
}

do_ssh_su() {
    do_ssh_s "$USER_NAME" -s "$@"
}

##

scriptname="$(basename "$scriptpath" .sh)" || \
    printf 'Failed using basename\n' >&2
test -n "$(PATH= printf 'x\n')" || \
    printf 'printf seems to only be provided by an external command which is insecure (passwords can be sniffed from args using ps)\n' >&2
memlockd_add_files

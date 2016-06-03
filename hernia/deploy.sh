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

exit_trap=''
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
scriptname='deploy' # override $(basename "$0" .sh) here, this may be running from a tempfile
info 'Sourced lib file "%s"\n' "$libfile"

source_vars '/root/external_vars.sh' || \
    die 'Failed sourcing external_vars file /root/external_vars.sh\n'
info 'Sourced external_vars file /root/external_vars.sh\n'

source_vars "$varsfile" || \
    die 'Failed sourcing vars file "%s"\n' "$varsfile"
info 'Sourced vars file "%s"\n' "$varsfile"

timestamp=$(date +%s)
info 'Generated timestamp "%s"\n' "$timestamp"
DEBIAN_FRONTEND=noninteractive; export DEBIAN_FRONTEND

which git >/dev/null 2>&1 && cd "$repo" >/dev/null 2>&1 || \
    die 'You need git and the (bare) repo present at "%s" for this to work\n' "$repo"
info 'Usable git exists\n'
info 'Changed to dir "%s"\n' "$repo"

git symbolic-ref HEAD "refs/heads/$branch" || \
    die 'Failed checking out the needed git-branch\n'
info 'Checked out the needed git-branch\n'

if test -n "$apt_source_filename" && test -n "$repo_pub_key_url"; then
    wget -O - --quiet "$repo_pub_key_url" | apt-key add - || \
        die 'Failed to retrieve repo signing public key\n'
    info 'Retrieved repo signing public key\n'

    printf '%s\n%s\n' "$apt_source_line_1" "$apt_source_line_2" >"$apt_source_filename" || \
        die 'Failed to create "%s"\n' "$apt_source_filename"
    info 'Created "%s"\n' "$apt_source_filename"

    aptitude --quiet=1 --assume-yes update || \
        die 'Failed to update apt\n'
    info 'Updated apt\n'

    aptitude --quiet=1 --assume-yes safe-upgrade || \
        die 'Failed to upgrade apt\n'
    info 'Upgraded apt\n'
fi

packages_custom_filenames=$(
    cd "$pkgssubdir" 2>/dev/null && \ls -1 *.deb 2>/dev/null | tr '\n' ' ' || :
)
packages_custom=$(
    printf '%s\n' "$packages_custom_filenames" | tr ' ' '\n' | cut -d_ -f1 | tr '\n' ' '
)
info 'Created custom packages list\n'

deps_custom=$(
    for _pkg in $packages_custom_filenames; do
        dpkg-deb -f "${pkgssubdir}/$_pkg" depends || exit 1
    done | tr -s ' ' '\n' | sed -e 's/,$//' | sort -u | tr '\n' ' '
) || \
    die 'Failed creating custom deps list\n'
info 'Created custom deps list\n'

packages_custom_prevent=$(a_if_in_b "$packages_custom_filenames" "$packages_prevent_service_autostart" '_')
packages_custom_noprevent=$(a_if_in_b -n "$packages_custom_filenames" "$packages_prevent_service_autostart" '_')
deps_custom_prevent=$(a_if_in_b "$deps_custom" "$packages_prevent_service_autostart")
deps_custom_noprevent=$(a_if_in_b -n "$deps_custom" "$packages_prevent_service_autostart")
packages_manual_prevent=$(a_if_in_b "$packages_manual" "$packages_prevent_service_autostart")
packages_manual_noprevent=$(a_if_in_b -n "$packages_manual" "$packages_prevent_service_autostart")
packages_auto_prevent=$(a_if_in_b "$packages_auto" "$packages_prevent_service_autostart")
packages_auto_noprevent=$(a_if_in_b -n "$packages_auto" "$packages_prevent_service_autostart")
info 'Created custom prevent/no-prevent lists\n'

if test -n "$pre_deploy_cmds"; then
    eval "$pre_deploy_cmds" || \
        die 'Failed executing pre_deploy_cmds\n'
    info 'Executed pre_deploy_cmds\n'
fi

# Create "don't auto-start service" script and chmod it when needed
cat >/usr/sbin/policy-rc.d <<EOF
#!/bin/sh
exit 101
EOF
if test -n "$deps_custom_noprevent"; then
    chmod -x /usr/sbin/policy-rc.d
    aptitude --quiet=1 --assume-yes --without-recommends install $deps_custom_noprevent || \
        die 'Failed to install custom deps "non-prevented autostart" packages\n'
fi
if test -n "$deps_custom_prevent"; then
    chmod +x /usr/sbin/policy-rc.d
    aptitude --quiet=1 --assume-yes --without-recommends install $deps_custom_prevent || \
        die 'Failed to install custom deps "prevented autostart" packages\n'
fi
info 'Installed custom deps\n'
if test -n "$packages_custom_noprevent"; then
    chmod -x /usr/sbin/policy-rc.d
    (
        cd "$pkgssubdir" && \
            dpkg -i $packages_custom_noprevent
    ) || \
        die 'Failed to install custom "non-prevented autostart" packages\n'
fi
if test -n "$packages_custom_prevent"; then
    chmod +x /usr/sbin/policy-rc.d
    (
        cd "$pkgssubdir" && \
            dpkg -i $packages_custom_prevent
    ) || \
        die 'Failed to install custom "prevented autostart" packages\n'
fi
info 'Installed custom packages\n'
if test -n "$packages_auto_noprevent"; then
    chmod -x /usr/sbin/policy-rc.d
    aptitude --quiet=1 --assume-yes install $packages_auto_noprevent || \
        die 'Failed installing automatic "non-prevented autostart" packages\n'
fi
if test -n "$packages_auto_prevent"; then
    chmod +x /usr/sbin/policy-rc.d
    aptitude --quiet=1 --assume-yes install $packages_auto_prevent || \
        die 'Failed installing automatic "prevented autostart" packages\n'
fi
info 'Installed auto packages\n'
if test -n "$packages_manual_noprevent"; then
    chmod -x /usr/sbin/policy-rc.d
    aptitude --quiet=1 --assume-yes install $packages_manual_noprevent || \
        die 'Failed installing manual "non-prevented autostart" packages\n'
fi
if test -n "$packages_manual_prevent"; then
    chmod +x /usr/sbin/policy-rc.d
    aptitude --quiet=1 --assume-yes install $packages_manual_prevent || \
        die 'Failed installing manual "prevented autostart" packages\n'
fi
info 'Installed manual packages\n'
rm -f /usr/sbin/policy-rc.d

if test -n "${deps_custom}$packages_auto"; then
    aptitude --quiet=1 --assume-yes markauto $deps_custom $packages_auto || \
        die 'Failed marking packages as automatically installed\n'
    info 'Marked packages as automatically installed\n'
fi

if test -n "${packages_custom}$packages_manual"; then
    aptitude --quiet=1 --assume-yes unmarkauto $packages_custom $packages_manual || \
        die 'Failed marking packages as manually installed\n'
    info 'Marked packages as manually installed\n'
fi

aptitude --quiet=1 --assume-yes install || \
    die 'Failed to do package autoremove\n'
info 'Did package autoremove\n'

iterate_pieces 2 '
    _softfail=0
    if printf %s\\n "$_b" | grep -q "^!"; then
        _softfail=1
        _b=$(printf %s\\n "$_b" | sed -e "s/^.//")
    fi
    service "$_a" "$_b" || \
        test 1 -eq $_softfail
' $services_post_install || \
    die 'Failed applying post-install service-actions\n'
info 'Applied post-install service-actions\n'

if test -n "${new_content_hash}${add_content_hash}$patch_content_hash"; then
    all_content_hash=$(
        printf '%s %s %s ' "$new_content_hash" "$add_content_hash" "$patch_content_hash" | \
            tr -s ' ' '\0' | \
            sort -z -u | \
            tr '\0' ' '
    )
    notnew_content_hash=$(
        printf '%s %s ' "$add_content_hash" "$patch_content_hash" | \
            tr -s ' ' '\0' | \
            sort -z -u | \
            tr '\0' ' '
    )

    exit_trap="$exit_trap"'test -z "$content_tempdir" || ! test -e "$content_tempdir" || rm -fr "$content_tempdir"
'
    trap "$exit_trap" EXIT
    content_tempdir="$(mktemp -d)"

    git archive --format=tar "HEAD:content" | \
        tar -C "$content_tempdir" --preserve-permissions --preserve-order -x -f - --wildcards "*/${this}/*" || \
            die 'Failed extracting content to tempdir\n'
    info 'Extracted content to tempdir\n'

    iterate_pieces 4 '
        # escape the replacement for use in RHS of sed-expression (normally would also
        # need s/$/\\n/ but varsfile values-format cannot include newlines anyway)
        _d="$(PATH= printf %s\\n "$_d" | sed -e '\''s/[\/&]/\\&/g'\'')"
        printf %s\\n "s/${_c}/${_d}/g" | \
            secure_sed "'"${content_tempdir}"'/${_a}/'"$this"'/${_b}$(! test patch = "$_a" || printf .diff)" || \
                return 1
    ' $replace_hash || \
        die 'Failed doing placeholder replacements in content tempdir\n'
    info 'Did placeholder replacements in content tempdir\n'

    iterate_pieces 2 '
        ! test -e "${_b}.'"$timestamp"'" || return 1
        mkdir -p "$(dirname "$_b")" || return 1
        _dosymlink=0
        if ! test -e "$_b"; then
            test -d "${_b}.0" || mkdir "${_b}.0" || return 1
            _dosymlink=1
        elif test -d "$_b"; then
            if test -h "$_b"; then
                _versioned_dirs="$(ls -1td /etc/${_b}.[0-9][0-9][0-9]* 2>/dev/null || :)"
                test -z "'"$past_timestamped_dirs_to_keep"'" || \
                    test '"$past_timestamped_dirs_to_keep"' -ge $(printf %s\\n "$_versioned_dirs" | wc -l) || \
                    rm -fr $(printf %s\\n "$_versioned_dirs" | tail -n +$(expr '"$past_timestamped_dirs_to_keep"' + 1) | tr "\\n" " ")
            else
                ! test -e "${_b}.0" || rm -fr "${_b}.0" || return 1
                mv -fT "$_b" "${_b}.0" || return 1
                _dosymlink=1
            fi
        else
            return 1
        fi
        test 0 -eq $_dosymlink || \
            ln -nfsT "$(basename "$_b").0" "$_b" || \
                return 1
    ' $all_content_hash || \
        die 'Failed ensuring symlinked directory structure for new, added and patched content\n%s\n' "$(explain_dir_structure)"
    info 'Ensured symlinked directory structure for new, added and patched content\n'

    iterate_pieces 2 '
        grep -q "^link:$_b\$" /root/hernia-rollback.log || \
            ln -nfsT "$(basename "$_b").0" "$_b" || \
                return 1
        ! test -e "${_b}.'"$timestamp"'" && \
            mkdir "${_b}.'"$timestamp"'" || \
                return 1
    ' $all_content_hash || \
        die 'Failed creating timestamped content directories\n'
    info 'Created timestamped content directories\n'

    iterate_pieces 2 '
        cp --reflink=auto -axfT "${_b}/" "${_b}.'"$timestamp"'" || \
            return 1
    ' $notnew_content_hash || \
        die 'Failed copying existing files for added and patched content\n%s\n' "$(explain_dir_structure)"
    info 'Copied existing files for added and patched content\n'

    iterate_pieces 2 '
        mergedirs "${_b}.'"$timestamp"'" "'"${content_tempdir}/new/$this"'/$_a"
    ' $new_content_hash || \
        die 'Failed exporting new content\n'
    info 'Exported new content\n'

    iterate_pieces 2 '
        mergedirs "${_b}.'"$timestamp"'" "'"${content_tempdir}/add/$this"'/$_a"
    ' $add_content_hash || \
        die 'Failed exporting added content\n'
    info 'Exported added content\n'

    _oldpwd="$(pwd)"
    iterate_pieces 2 '
        cd "${_b}.'"$timestamp"'" && \
            patch -p1 <"'"${content_tempdir}/patch/${this}"'/${_a}.diff" && \
            cd "'"$_oldpwd"'" || \
                return 1
    ' $patch_content_hash || \
        die 'Failed applying patch content\n'
    info 'Applied patch content\n'
fi

iterate_pieces 3 '
    test -z "$_b" || \
        chmod -R "$_b" "${_a}.'"$timestamp"'" || return 1
    test -z "$_c" || \
        chown -HR "$_c" "${_a}.'"$timestamp"'" || return 1
' $perms_hash || \
    die 'Failed updating perms and ownership\n'
info 'Updated perms and ownership\n'

if test -n "${new_content_hash}${add_content_hash}$patch_content_hash"; then
    iterate_pieces 2 'vdiff "$_b" "${_b}.'"$timestamp"'"' $all_content_hash

    iterate_pieces 2 '
        printf link:%s\\n "$_b" >>/root/hernia-rollback.log && \
            ln -nfsT "$(basename "$_b").'"$timestamp"'" "$_b" || \
                return 1
    ' $all_content_hash || \
        die 'Failed pivoting content to production\n'
    info 'Pivoted content to production\n'

    iterate_pieces 2 '
        info '\''Reverse-chronological destination directories for "%s":\n'\'' "$_a"
        \ls -ltd "$_b" "$_b".* | sed -e "s/^/   /"
    ' $all_content_hash
fi

iterate_pieces 2 '
    _softfail=0
    if printf %s\\n "$_b" | grep -q "^!"; then
        _softfail=1
        _b="$(printf %s\\n $_b | sed -e "s/^.//")"
    fi
    service "$_a" "$_b" || \
        test 1 -eq $_softfail
' $services_post_deploy || \
    die 'Failed applying post-deploy service-actions\n'
info 'Applied post-deploy service-actions\n'

if test -n "$post_deploy_cmds"; then
    eval "$post_deploy_cmds" || \
        die 'Failed executing post_deploy_cmds\n'
    info 'Executed post_deploy_cmds\n'
fi

info 'Finished OK. Remember to cleanup the older un-symlinked\ndestination-directories when new versions are confirmed OK\n'

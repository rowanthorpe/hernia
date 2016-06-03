TODO
====

QUICK
-----

### Add optional handling of args by receive-hook for specific re-deploys

Add functionality so when the git receive-hook is run directly with args it only
iterates re-deploying those steps, rather than iterating all (default).

### Use binary-friendly way to copy new/added content (for images, etc)

Presently this just uses printf of escaped content within ssh-and-sudo. Obviously
shell-strings don't handle embedded nulls (\0) so this will break for files with
nulls. scp either happens as user or as root, but we allow ssh/scp only as user,
with sudo to root. scp-ing files requiring root involves:

* copy file to tempfile as user in user-homedir
* ssh and sudo to root
* mv tempfile to intended location
* chown it to root (or other)

### Check for other manual system tweaks needed in provision

In provision.sh where the hostname, fqdn, etc are updated, see if any other
file updates are worth making (particularly thinking of systemd stuff). I will
check my earlier devops code-snippets for reference (CentOS work in puppet, etc).

### Get country code by prompt, not from the existing sources.list

At the moment the country code is grokked from the existing sources.list which
is a bit unreliable. It would be better to prompt for it (with local country as
default), then update /etc/apt/sources.list, /etc/locale.gen, etc with that.

### In run.sh add run_dir, log_dir, daemon_user, daemon_group to vars.sh

At the moment I just (ab)use daemon_name for these in the script, but that
only happens to work for now. It is too restrictive, they should be
configurable instead.

### Get meaningful default LOCALE_GEN and TZ_DATA values (from local locale?)

At the moment the defaults for those values are hard-coded. Get reliable
defaults from the local environment instead.

### Auto-generate content-hashes

Auto-generate things like patch\_content\_hash, new\_content\_hash, etc based on
files in the corresponding source directories. Then they don't need to be
specified in the vars files. replace_hash can't be auto-generated but could
be sanity-checked (if file matches `\<__[A-Z]\+__\>` without corresponding entry
in hash...).

### Make some fields in pseudo-hashes comma-separated multi-fields

I already did this before in some places, but got rid of it for the sake of
simplicity as it wasn't used much. Re-adding this (to wherever makes sense)
would allow compacting down some vars files by sub-iterating the fields instead
of repetitive config entries.

HIGH PRIORITY
-------------

MEDIUM PRIORITY
---------------

### Use quote_wrap everywhere

Use quote_wrap & quote_wrap_p eveywhere instead of arbitrary single-quoting in
some places. Would be better to rename them to qw and qwp to reduce verbosity.

### Use quilt to maintain patch-content directory

Update format of patch-content directory to support using quilt for maintenance
rather than doing it manually like I do at the moment.

### Add service restarts to post-receive rollback exit trap

This isn't as easy as the config-file symlink resets, order matters so
"sort -u" won't work. They should happen _after_ the symlinking.

LOW PRIORITY
------------

### Add preseed directory to base of repo

To avoid hardcoding preseed actions, add this with debconf-set-selections
content, in files named after the related package. Same idea as the pkgs
directory: e.g.

>     preseed/_provision/exim4-config:
>     
>     exim4-config	exim4/mailname	string	example.com
>     exim4-config	exim4/dc_relay_domains	string
>     ...

### Make sip provider settings more configurable

At the moment there are a few remaining presumptions in the freeswitch conf
about the sip provider settings (e.g. the username is set to the same as the
did-number, etc). It would be a quick task to abstract more of these out into
vars.sh, to be useful for providers other than ours.

### Prevent hibernation of local machine during run

memlockd is used to prevent swapping private data to disk, both locally and
remotely. There is still a risk of private data hitting disk if the local
machine is hibernated during a run. I haven't worked out a simple way to
forcibly prevent hibernation yet, but that would probably only ever be an
issue locally, and generally only on an effectively "single-user" laptop, so
it's probably OK to treat that as very low priority.

### arp and eb stuff in ferm config

Investigate if worth configuring those at the moment.

Hernia
======

What is it
----------

A configurable server provision & (re)deployment tool. All pre-commit automation happens
via recursive Makefiles, all provisioning is done via ssh, and all deployment is done
within a git receive-hook (which is setup during provision, along with the git repo).

To provision a server
---------------------

 * Ensure that DNS settings for your domain are correct and consistent with what Hernia
   will expect (otherwise setup of things like email and certbot will fail). First copy
   zonefile.txt.template to zonefile.txt and edit the placeholder values. This is
   sourced for meaningful defaults, and can also be used as a BIND zonefile, or at least
   for reference when setting up DNS records.

 * Fire up a minimal Debian Jessie ssh-server the usual way. If you don't have ssh
   access at all (only console-login access as root e.g. over VNC) then do the following
   as root manually (enter new password twice when prompted). The edit to
   PermitRootLogin is necessary on a vanilla Debian install as the default setting is
   "without-password":

        passwd
        apt-get --yes install ssh
        sed -i -re 's/^(#*[ \t]*)?PermitRootLogin[ \t].*$/PermitRootLogin yes/' \
            /etc/ssh/sshd_config
        service ssh restart

 * Once any of the following are setup the provision script will do the rest:
   root-password-ssh, root-key-ssh, $USER_NAME-password-ssh, or $USER_NAME-key-ssh.
   If $USER_NAME-key-ssh isn't already setup manually, you must have your private &
   public key in their usual location in your local .ssh dir - the public key will be
   copied to the server. $USER_NAME is what you enter in the prompt at the start of
   provision. Of course if starting from password-access you will be required to enter
   the password once after answering the prompts, then the rest will be
   non-interactive.

 * To customize deployments edit & commit changes to the files in vars/. They are
   iterated in alphanumeric order. Each variable is self-explanatory, or has
   explanatory comments.

 * Copy external_vars.sh.template to external_vars.sh & for private data edit that
   file, but don't try to commit it - it is gitignored anyway, and will be scp-ed
   separately to the server. The template file is in git though.

 * Run "hernia/provision.sh" from the base of the local git repo, answering the
   prompts at the beginning.

 * The server repo should now be setup to auto-deploy whenever you do "git push vm",
   and if you answered "yes" to the trigger-a-deploy question, then a first deploy
   will automatically run at the end of provisioning.

 * All steps of provision & deployment should be idempotent with adequate rollback
   for failures, so you should be able to just rerun after a failed or interrupted
   provision or deploy, and/or after completion. Re-deployment will auto-trigger
   whenever a git push is done to the server. This will of course overwrite any
   manual edits made in the hernia-controlled config-dirs, so don't do that.

 * Be warned that provisioning is designed to be run on a new server, or to
   effectively "reset" a used server. Therefore it *purges* packages down to a
   known starting point and deployment then works up from there, so if you run
   provision on a heavily loaded/pre-configured server, expect to lose a lot of
   existing data. Things like existing users & homedirs are retained though.

Directory layout of the deployed files
--------------------------------------

For each config dir updated by Hernia during deployment (by "new", "add" or
"patch") the layout on the filesystem will be:

    "dir"                    = symlink -> "dir.[LATEST_TIMESTAMP]"
    "dir.[LATEST_TIMESTAMP]" = directory
    "dir.0"                  = pre-deployment directory

If the directory was also updated during provisioning, then:

    "dir.-1"                 = pre-provisioning directory

The timestamp in the directory-names will be the unix-time of when the
deployment was made (not of the latest commit). The symlinks are to allow
easy atomic deploy and manual rollback (by changing the symlink) if something
goes wrong when using the new configuration. For manual rollback two useful
commands are:

    ls -ltd "$dir".*
    ln -nfsT "$(basename "$dir").[TIMESTAMP_YOU_WANT]" "$dir"

How each tool works
-------------------

 * Makefile

     * provision.sh (see below) sets up a git pre-commit hook which runs "make" in
       the basedir. This can be used to auto-build/check dependent files before commit.
       It can also be run manually of course. One common idiom is that README/TODO
       files are edited in the markdown files, and "make" generates the html files.

 * provision.sh

     * Gets a bare minimal debian jessie server up to a usable point for deployment:

         * Key-based user-ssh access

         * Passwordless sudo for the user

         * The repo as a bare-remote on the server

         * Packages necessary for deploy steps installed

         * The post-receive hook in place to trigger auto-deploys on git-push

         * Email configured to encrypted-send logs, cron-output, etc to your configured
           address

     * Triggers a first deployment if requested

 * receive-hook

     * checks repo is on correct branch

     * updates itself from repo if necessary

     * extracts hernia-files, etc from repos to tempfiles for use

     * runs deploy tool as root

     * runs run tool as root (if configured to)

 * deploy.sh

     * makes necessary config changes (e.g. apt)

     * installs configured packages

     * checks/sets-up deploy-directory structure

     * exports files from git

     * modifies config file if configured to

     * does post-deploy actions if any are configured

 * run.sh

     * runs daemon with configured options

 * lib.sh & vars.sh

     * supplemental files sourced by the other hernia tools

 * external_vars.sh.template

     * should be copied to (gitignored) external_vars.sh, then edited, and gets
       copied to /root/ by provision.sh (some auto-vars are also injected
       during provision)

 * zonefile.txt.template

     * should be copied to (gitignored) zonefile.txt, then edited, and gets
       sourced for meaningful defaults for provision & deploy (and can be used
       as a BIND-style zonefile if you want, or at least should be consistent
       with your DNS settings)

Other notes
-----------

 * For my own purposes this does what I want, but for more general purposes I
   would class it somewhere between Alpha and Beta. I have refined it to behave
   quite robustly, but some steps are still quite "opinionated", and could do
   with being more user-friendly/generic, and making less case-specific
   presumptions.

## How to contribute

Fork the repository, commit your changes to your fork and create merge request.

**NOTE:** This repository is private because it contains information about
internal infrastructure. Additionally, these scripts are designed for our
internal needs only and don't help the community with their generic
setups.

## Synchronizing mediums

`rsync.pl` script is used to synchronize repositories and iso files from the build server and trigger job in openQA. It contains profiles defined in `$config` variable and defined in `set_config` subroutine. This configuration contains settings required for the proper synchronization. If there is a common part of profile, then `mapto` attribute can be used to define all common settings and the reused in other profiles.

Now it's also possible to sync repositories only partly. For example, if we just need a single package from the repo, it's a waste to sync full repo. For that one can simply provide array reference with the list of packages to `_reposync` method (see the subroutine documentation). As per notation, we use `_DEBUG`, `_SOURCE` post-fixes for the repo variables. E.g. for the Tumbleweed we set:
```
"REPO_OSS" : "openSUSE-Tumbleweed-oss-i586-x86_64-Snapshot20181219",
"REPO_OSS_DEBUGINFO" : "openSUSE-Tumbleweed-oss-i586-x86_64-Snapshot20181219-debuginfo",
"REPO_OSS_SOURCE" : "openSUSE-Tumbleweed-oss-i586-x86_64-Snapshot20181219-source",
"REPO_OSS_SOURCE_PACKAGES" : "coreutils",
```

where `_PACKAGES` post-fix defines list of packages available in the repository. It should be used in the test code to cross-check package availability and report clear error message.

## Wrapper scripts

For different kind of tasks we have different wrapper scripts. These scripts names start with **openqa-iso-sync-**. Common part which is reused in multiple scripts is extracted to **openqa-iso-sync-common**. The task which each of this scripts do is calling `rsync.pl` with correct set of parameters. Main task of the wrapper scripts is to avoid synchronization when build set is not complete, in progress, etc.

## Adding profile for SLE15 staging

With SLE 15, in order to test right product, we also have to sync four repositories, which are then used during installation. This was not required before, as we had single media. It introduced same challenges as we have for functional openQA job group, as we may sync repositories when not all packages are uploaded to it. Using current architecture of the solution, it's required to create profiles for each staging, as if `rsync.pl` script is called, it will try to sync mediums and trigger jobs accordingly. At the moment there profiles for following stagings: A-H, S, V, Y.

If new staging for SLE 15 will be added, there are two changes to be introduced:
1. Add profile to `rsync.pl` similarly to existing profiles:
```perl
sle15_staging_m => {
    mapto => 'sle15_staging',
    major_version => '15',
    staging_letter => 'M',
    sp_version => undef
}
```

**NOTE:** Please, use same naming format as staging letter is extracted from profile name to verify artifacts status.
2. Add created profile to the wrapper script default set of parameters:
`
[ $# -gt 0 ] || set -- sle15_staging_{a..h} sle15_staging_m sle15_staging_s sle15_staging_v sle15_staging_y caasp_staging
`

**NOTE:** It's also possible to define parameters when wrapper script is called, then second step is not required.

## How to test your changes

As stated above, there are two components which are independent from each other.
Wrapper scripts are triggered by cron job, hence to test them, one can replace `rsync.pl`
call with `echo`.

`--host` option is used to specify openqa host where images should be synced to.
If not specified isos are synced but not posted.

`rsync.pl` has multiple options which can help with testing. The first check of the
changes can be done using `--dry` option. It will prevent `rsync.pl` from synchronizing
and triggering anything.
```bash
./rsync.pl --dry --host openqa.suse.de --add-existing --verbose sle15_sp0
```
In case you've introduced some changes to the sync functions, it makes sense to run synchronization
without triggering any jobs on openQA:
```bash
./rsync.pl --host openqa.suse.de --no-trigger --verbose sle15_sp0
```
In case the build is already synced, one can use `--add-existing` option to verify
code changes.

**NOTE:** if you don't have working directory in `@INC`, include it using `-I`.
For example:
```bash
perl -I . rsync.pl --dry --host openqa.suse.de --add-existing --verbose sle15_sp0
```

There are also local tests which are executed in the CI system and can be
called manually with

```bash
make test
```

If your changes affects multiple distributions, to be on safe side, please, test
your changes against all affected profiles. The names can be found in wrapper scripts
(the ones with openqa-iso-sync in the name), simply find `rsync.pl` call and get
parameters from it.
For example, for openSUSE profiles used can be found in `openqa-iso-sync` bash wrapper script.

To test the instructions within the .gitlab.yml file call

```
sudo gitlab-runner exec docker 'deploy to o3'
```

or any other corresponding target.


## Other useful options

For debugging issues, `rsync.pl` has `--verbose` option to get additional output during
the execution.

`--no-obsolete` option allows to avoid obsoleting unfinished jobs of
potentially old build. ` --deprioritize-or-cancel` provides a functionality to deprioritize
jobs instead of obsoleting.

If test requires setting some additional variables, those can be set using `--set KEY=VALUE`
option.

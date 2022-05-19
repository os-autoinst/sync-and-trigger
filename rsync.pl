#!/usr/bin/perl -w
# Copyright SUSE LLC
# SPDX-License-Identifier: MIT

=head1 rsync.pl

rsync.pl - script to sync iso images and repos for openqa

=head1 SYNOPSIS

rsync.pl [OPTIONS] [modules]

=head1 OPTIONS

=over 4

=item B<--host> HOST

openqa host. If not specified isos are synced but not posted to openqa

=item B<--dry>

dry run, don't actually sync files

=item B<--add-existing>

normally isos that are already on disk are not posted again to openqa. This
option post them anyways.

=item B<--no-obsolete>

do not obsolete unfinished jobs of a potentially older build.

=item B<--no-trigger>

Only sync, do not trigger actual jobs.

=item B<--deprioritize-or-cancel>

Do not immediately obsolete jobs of old builds but rather deprioritize them up
to a configurable limit of priority value corresponding roughly to number of
builds which may still run while a new one is triggered. See openQA
documentation for details.

=item B<--deprioritize-limit> PRIORITY_LIMIT

The limit of openQA priority value up to which existing jobs are
deprioritized. If the priority of the job reaches this limit the job is
cancelled rather than deprioritized. Needs B<--deprioritize-or-cancel>.

=item B<--set> KEY=VALUE

pass additional settings that override values from job templates. TEST and
MACHINE are special. openQA will filter job templates according to that.

=item B<--iso> FILE

only sync specified FILE (if found)

=item B<--destdir> DIR

override default iso dir (/var/lib/openqa/factory/iso)

=item B<--repodir> DIR

override default repo dir (/var/lib/openqa/factory/repo)

=item B<--repourl> URL

URL to reach repos (default HOST/assets/repo, fallback http://openqa.opensuse.org/assets/repo)

=item B<--help, -h>

print help

=item B<--man>

show full help

=item B<--verbose>

verbose output

=back

=head1 DESCRIPTION

$ rsync.pl -v

$ rsync.pl -v --host localhost

$ rsync.pl --host localhost totoest

$ rsync.pl --host localhost totoest --iso openSUSE-FTT-NET-x86_64-Snapshot20140903-Media.iso

$ rsync.pl --host localhost totoest --iso openSUSE-FTT-NET-x86_64-Snapshot20140903-Media.iso --set TEST=textmode

=cut

use strict;
use warnings 'FATAL';
package rsync;
use Data::Dump qw/dd pp/;
use Getopt::Long;
Getopt::Long::Configure("no_ignore_case", "gnu_compat");

use File::Basename qw/basename dirname/;
use File::Rsync 0.48;
use File::Temp qw/tempfile/;
use JSON;
use Mojo::URL;
## Adding script directory to locate extracted modules. This directory is used on o3 and osd
## /usr/share/openqa/lib is required for OpenQA::Client
use FindBin '$Bin'; use lib "$Bin";
use lib "/usr/share/openqa/lib";
use OpenQA::Client;
use Mojo::UserAgent;
use MIME::Base64 qw/encode_base64url/;
use Digest::file qw/digest_file_hex/;

use feature "state";

our %options;

sub usage {
    my $r = shift;
    eval "use Pod::Usage;";
    if ($@) {
        die "cannot display help, install perl(Pod::Usage)\n";
    }
    pod2usage($r);
}

# give it a speaking name in case we see it in output
our $major_version = 'DEFAULT';
our $version_in_staging = 'DEFAULT';

GetOptions(
    \%options,
    "verbose|v",
    "destdir|d=s",
    "repodir=s",
    "host=s",
    "repourl=s",
    "set=s%",
    "iso=s" => sub { $options{iso}->{$_[1]} = 1 },
    "add-existing",
    "no-obsolete",
    "no-trigger",
    "deprioritize-or-cancel",
    "deprioritize-limit=i",
    "no-extract",
    "force",
    "dry",
    "man" => sub { usage({-verbose => 2, -exitval => 0})},
    "help|h",
    "key=s",
    "secret=s"
) or usage(1);

#usage(1) unless @ARGV;
usage(0) if ($options{'help'});
my @todo = @ARGV;

$options{destdir} ||= '/var/lib/openqa/factory';
$options{repodir} ||= $options{destdir}.'/repo';
$options{"deprioritize-limit"} ||= 100;

(-o $options{destdir} || $options{dry}) || die "$options{destdir} is not owned by current user. This is probably not what you want (use '--force' otherwise)"
    unless $options{force};

my $openqa_url = Mojo::URL->new('http://localhost');
my $openqa_post_retry_count = 3;
my $openqa_post_retry_timeout_seconds = 60;
my $client;

$options{host} //= $openqa_url->host;
if ($options{'host'} !~ '/') {
	$openqa_url = Mojo::URL->new();
	$openqa_url->host($options{'host'});
	$openqa_url->scheme('http');
} else {
	$openqa_url = Mojo::URL->new($options{'host'});
}
$client = OpenQA::Client->new(apikey => $options{'key'}, apisecret => $options{'secret'}, api => $openqa_url->host);

my $scc_url = $openqa_url->clone()->host('scc.'.$openqa_url->host);

$options{repourl} ||= $openqa_url.'/assets/repo';

sub dryrun {
    return $options{dry};
}

# return full path to save file as based on name
sub dirfor {
    my ($name) = @_;
    my $type = 'hdd';
    if ($name =~ /\.iso$/) {
        $type = 'iso';
    }
    if ($name =~ /\.(appx|box|tar\.[^.]+)$/) {
        $type = 'other';
    }
    return join('/', $options{destdir}, $type, $name);
}

sub use_fake_scc {
    my ($settings) = @_;
    return 1 if $settings->{VERSION} =~ /12-SP[2-9]/ || $settings->{VERSION} =~ /^15/;
    return 0;
}

sub extract_iso_as_repo {
    my ($file) = @_;
    # Extract iso
    my $iso_repodir = $options{repodir}."/".basename(shift, '.iso');
    unless(-d $iso_repodir) {
        print "Extracting ".$file."\n" if $options{verbose};
        my $tmp = "$iso_repodir.new";
        unless (dryrun() || $options{'no-extract'}) {
            mkdir $tmp;
            if (system("bsdtar", "xf", $file, "-C", $tmp) == 0) {
                rename $tmp, $iso_repodir;
            }
        }
    }

    if ($file =~ /s390x/) {
        print "removing unused s390x installation ISO $file\n";
        if(!dryrun()) {
            unlink($file) or warn "Could not unlink $file: $!\n";

            if ( $file =~ /(?:Build|Snapshot)[^-]+/ ) {
                $file =~ s/(?:Build|Snapshot)[^-]+/CURRENT/;
                print "removing CURRENT hardlink $file\n";
                unlink($file) or warn "Could not unlink $file: $!\n";
            }
        }
    }
    return basename($iso_repodir);
}

sub rename_for_staging_sync_override {}

sub rename_for_staging_sync {
    my ($name, $staging) = @_;
    $name = rename_for_staging_sync_override($name, $staging, $version_in_staging);
    # Replace build and return
    $name =~ s/Build/Build$staging\./;
    return $name;
}

sub repo_name_override {}

sub sync_addons {
    my ($settings) = @_;

    for my $i (1..6) {
        my $key = "ISO_$i";
        my $src = $settings->{$key};
        if (!$src) {
            $key = "_$key";
            $src = $settings->{$key};
        }
        if ($src) {
            my $iso = basename($src);
            my $repo = basename($iso, '.iso');
            # Rename staging iso
            if(my $staging = $settings->{STAGING}) {
                $iso = rename_for_staging_sync $iso, $staging;
            }
            my $dest = dirfor($iso);
            if (! -e $dest) {
                print "syncing $dest\n" if $options{verbose};
                if (!dryrun()) {
                    my $rsync = File::Rsync->new(src => $src, timeout => 3600, dest => $dest);
                    $rsync->exec or warn "rsync $src -> $dest failed";
                }
            }
            if (!use_fake_scc($settings)) {
                extract_iso_as_repo($dest);
            }
            if ($key =~ m/^_/) {
                # remove temporary ISO keys
                delete $settings->{$key};
            } else
            {
                $settings->{$key} = $iso;
                # get the checksum of iso/hdd
                if (!dryrun() && -e $dest) {
                    my $checksum_sha256 = digest_file_hex($dest, "SHA-256");
                    my $checksum_key = "CHECKSUM_$key";
                    $settings->{$checksum_key} = $checksum_sha256;
                }
                else {
                    warn "File $dest not found, checksum won't be calculated and set";
                }
                if (!use_fake_scc($settings)) {
                    my $repokey = $key;
                    $repokey =~ s,ISO_,REPO_,;
                    warn "BUG: $repokey exists, will be overwritten with $repo!" if ($settings->{$repokey});
                    $settings->{$repokey} = repo_name_override($repo);
                }
            }
        }
    }

    warn "BUG: REPO_0 exists, will be overwritten with ISO!" if ($settings->{REPO_0});
    # WSL test suites doesn't use any ISO
    $settings->{REPO_0} = extract_iso_as_repo(dirfor($settings->{ISO})) if ($settings->{ISO});
    if ($settings->{ARCH} eq 's390x') {
        print "unsetting unused s390x installation ISO: $settings->{ISO}\n";
        delete $settings->{ISO};
    }
}

# input:
# {
#   location => rsync path
#   targetname => name in $repodir
#   expect_buildid => (optional) buildid the repo must have
#   buildid_variable => (optional), which capture group from
#                       buildid_pattern to use for the build
#                       id, default 'build'
#   buildid_pattern => a regexp that is used to extract the build
#                      id from the media.1/build file. Must have at
#                      least one capture group that sets
#                      buildid_variable
#   packages => array reference with names of the packages to be synced from
#               the repo, not listed packages are filtered out. Remaining
#               directories and files are synced to keep repo consistent
sub _reposync {
    my %args = @_;

    print "reposync $args{location}\n  -> $args{targetname}\n" if $options{verbose};

    unless ($args{location} && $args{targetname}) {
        dd \%args;
        warn "location or targetname missing";
        return 0;
    }

    my $rsync = File::Rsync->new(timeout => 3600);

    if ($args{expect_buildid}) {
        unless ($args{buildid_pattern}) {
            warn "buildid_pattern missing";
            return 0;
        }

        my ($fh, $tmp) = tempfile("reposync-XXXXXX", TMPDIR => 1);
        unless ($tmp) {
            warn "couldn't create tmp file: $!";
            return 0;
        }

        # read media.1/build to check if the correct repo is available
        $rsync->exec(src => $args{location}.'/media.1/build', dest => $tmp, inplace => 1);
        if ($rsync->err) {
            printf "checking for new product builder format in %s\n", $args{location} if $options{verbose};
            $rsync->exec(src => $args{location}.'/media.1/media', dest => $tmp, inplace => 1);
            if ($rsync->err) {
                warn 'failed to sync media file in new product builder format in ' . $args{location} . '/media.1/media';
                print $rsync->err;
            }
            my $dummy = <$fh>;
        }
        print $rsync->err if $rsync->err;

        unless ($rsync->status == 0) {
            warn "rsync failed";
            return 0;
        }

        my $buildid = <$fh>;
        unless ($buildid) {
            warn "got empty buildid";
            return 0;
        }
        chomp $buildid;
        close $fh;
        unlink $tmp;

        unless ($buildid =~ $args{buildid_pattern}) {
            warn "invalid build id $buildid\n";
            return 0;
        }
        my $build = $+{$args{buildid_variable}//'build'};
        unless ($build eq $args{expect_buildid}) {
            print "build '$build' of repo '$buildid' doesn't match iso with build '$args{expect_buildid}'\n" if $options{verbose};
            return 0;
        }
    }

    my $dest = join('/', $options{repodir}, $args{targetname});
    if (-e $dest) {
        warn "$dest already exist, not syncing again!\n";
        return 1;
    }
    my $current = $dest;
    $current =~ s/(?:Build|Snapshot)[^-]+/CURRENT/;
    my $link = readlink($current);
    if ($link && $link !~ /^\//) {
        $link = join('/', $options{repodir}, $link);
    }

    printf "  syncing %s\n", $dest if $options{verbose};

    if (-e $dest.'.new') {
        print "    $dest.new exists, resuming previous sync ...";
    }
    my @rsync_args = (
            delete => 1,
            verbose => $options{verbose},
# some filter for debugging
#            filter => [
#                '+ /*',
#                '+ /media.1/**',
#                '+ /boot/**',
#                '+ /suse/setup/',
#                '+ /suse/setup/**',
#                '- *',
#            ],
            recursive => 1,
            links => 1,
            perms => 1,
            times => 1,
            specials => 1,
            ipv4 => 1,
            src => $args{location},
            dest => $dest.'.new/',
    );
    if($args{packages}) {
        my $packages_ref = $args{packages};
        my @packages = @$packages_ref if $packages_ref;
        my @filter = (); # list of filters to be used

        for my $pkg (@packages) {
           push @filter, "+ $pkg*";
        }
        # Exclude all directories which contain packages to include only required ones
        my @exclude = ( '- aarch64/*',
                        '- armv7hl/*',
                        '- i586/*',
                        '- i686/*',
                        '- noarch/*',
                        '- nosrc/*',
                        '- ppc64le/*',
                        '- s390x/*',
                        '- src/*',
                        '- x86_64/*' );
        push(@filter, @exclude);
        # Add filter to rsync arguments
        push @rsync_args, filter => \@filter;
    }
    push @rsync_args, 'link-dest', [ $link ] if $link;
    # If have dry run only list items we would sync
    my $ret = dryrun() ? $rsync->list(@rsync_args) : $rsync->exec(@rsync_args) ;
    print $rsync->err if $rsync->err;
    print $rsync->out if $options{verbose};
    unless (defined $ret && $ret) {
        warn "rsync failed $ret\n";
        return 0;
    }
    unless(rename($dest.'.new', $dest)) {
        warn "couldn't rename $dest.new -> $dest: $!\n";
        return 0;
    }
    unlink($current);
    unless(symlink(basename($dest), $current)) {
        warn "symlink $dest: $!";
    }
    print "sync done\n" if $options{verbose};
    return 1;
}

sub skip_repo_override {}

# rsync configuration
# identifier => {
#
## enable/disable. 1 to disable entry
#     skip => INTEGER
#
## rsync base url
#     path => STRING
#
## rsync include/exclude patterns, see rsync manpage
#     filter => [ STRING, ...]
#
## function to rename iso image (optional). First parameter original
## file new, second parameter full rsync path.
#     rename => CODE
#
## function to get setting for image. First parameter original
## file new, second parameter full rsync path. Expected to return hash ref
#     settings => CODE|HASH
#
## function to sync repository. First parameter is settings
##    reposync => CODE
# }
our $config = {};
# dynamically load all modules in the script directory matching the pattern
# and define override methods if any
my @module_paths = glob dirname(__FILE__) . "/rsync_*.pm";
require $_ foreach(@module_paths);
my @modules = map { basename($_) =~ s/\.pm//r } @module_paths;
sub set_config { &{\&{"${_}::set_config"}}() foreach(@modules); }
our $override = Sub::Override->new();
&{\&{"${_}::override_methods"}}() foreach(@modules);
set_config;

@todo = grep { ! $config->{$_}->{skip}//0 } keys %$config unless @todo;

my @tosync;
for my $flavor (@todo) {

    unless ($config->{$flavor}) {
        warn "$flavor does not exist!\n";
        next;
    }

    print "Syncing '$flavor'\n" if $options{verbose};
    my $staging_letter;
    my $sp_version;

    if ((defined $config->{$flavor}->{major_version}) and (defined $config->{$flavor}->{sp_version})) {
        $major_version = $config->{$flavor}->{major_version};
        $sp_version = $config->{$flavor}->{sp_version};
    } else {
        # defaults to make you add mapto if not existant
        $major_version = '11';
        $sp_version = 'SP1';
    }

    $staging_letter = $config->{$flavor}->{staging_letter} if (defined $config->{$flavor}->{staging_letter});
    $flavor = $config->{$flavor}->{mapto} if (defined $config->{$flavor}->{mapto});

    $version_in_staging = "$major_version" . ($sp_version ? "-$sp_version" : '');

    # expand the new variables
    set_config;

    my $path = $config->{$flavor}->{path};
    # Add staging letter if required
    my $src = $staging_letter ? $path . $staging_letter : $path;
    my $rsync = File::Rsync->new(src => $src, recursive=>1, filter => $config->{$flavor}->{filter}, timeout => 3600);
    my @rlist = $rsync->list;

SYNCLIST:
    for my $name (@rlist) {
        chomp $name;
        $name =~ s/\\n$//;
        $name =~ s/.* //;
        # XXX: This is the top-most 'guardian' for media filename extensions
        next unless $name =~ /\.(?:iso|qcow2|qcow2\.xz|vmdk|vmdk\.xz|vhdx\.xz|vhdfixed\.xz|raw\.xz|vhdx|tar.[^.]+|box|appx)$/;
        my $newname = basename($name);
        unless ($config->{$flavor}->{settings}) {
            warn "settings not defined for $name!";
            next;
        }
        next if skip_repo_override(version_in_staging => $version_in_staging, name => $name, repodir => $options{repodir}, rlist => \@rlist);
        my $settings = $config->{$flavor}->{settings};
        if (ref $settings eq 'CODE') {
            $settings = &$settings($newname, $name);
        }
        unless ($settings && ref $settings eq 'HASH') {
            warn "settings for $name is neither hash nor sub!\n";
            next;
        }
        if ($options{set}) {
            @{$settings}{keys %{$options{set}}} = values %{$options{set}};
        }

        if ($config->{$flavor}->{rename}) {
            $newname = $config->{$flavor}->{rename}($newname, $name);
            unless ($newname) {
                print STDERR "ERROR: empty new name for $name, skipped.\n";
                next;
            }
        }

        next if (exists $options{iso} && ! $options{iso}->{$newname});

        if (!defined $settings->{ISO} && $newname !~ /\.appx$/) {
                $settings->{ISO} = $newname;
        } elsif (!$settings->{ISO}) {
                # XXX special hack introduced for VMDP. Remove iso setting if
                # it's empty. This allows for the job templates to set the ISO.
                delete $settings->{ISO};
        }

        my $path = $path.$name;

        if (-e dirfor($newname)) {
            unless ($options{"add-existing"}) {
                print STDERR "$newname exists, skipped\n" if $options{verbose};;
                next;
            }
        }

        for my $repo (sort grep { /^REPO_\d+$/ } keys %$settings) {
            $repo = basename($settings->{$repo});
            my $repodir = join('/', $options{repodir}, $repo);

            if (! -e $repodir) {
                if ($config->{$flavor}->{reposync}) {
                    $config->{$flavor}->{reposync}($config->{$flavor}, $settings);
                }
                # If not dry run or if sync failed, so no directory created
                if (! dryrun() && ! -e $repodir) {
                    print STDERR "$newname: repo $repo missing, skipped\n";
                    next SYNCLIST;
                }
            }
        }

        my $syncdata = {
            src => $path,
            dest => $newname,
            settings => $settings
        };
        for my $i (qw/notify sync_addons compute_register/) {
            if ($config->{$flavor}->{$i}) {
                $syncdata->{$i} = $config->{$flavor}->{$i};
            }
        }
        push(@tosync, $syncdata);
    }

    if ($rsync->err) {
        print STDERR "+++ Rsync errors:\n";
        print STDERR join("", $rsync->err);
    }
}

{
    my @toregister;
    my $rsync = File::Rsync->new(timeout => 3600);
    while (my $cfg = shift @tosync) {
        print "  $cfg->{src}\n  -> $cfg->{dest}...\n" if $options{verbose};

        my $dest = $cfg->{dest};
        my $link;
        if ( $dest =~ /(?:Build|Snapshot)[^-]+/ ) {
            $link = $dest;
            $dest =~ s/(?:Build|Snapshot)[^-]+/CURRENT/;
        }
        my $success;
        unless (dryrun() || -e dirfor($link||$dest)) {
            $rsync->exec(checksum => 1, verbose=>1, src => $cfg->{src}, dest => dirfor($dest));
            print $rsync->err if $rsync->err;
            print $rsync->out if $options{verbose};
            $success = $rsync->status == 0;
        } else {
            $success = 1;
        }
        if ($success) {
            if (!dryrun() && $link) {
                $link = dirfor($link);
                if (-e $link) {
                    # XXX: checksum and do nothing?
                    unlink $link;
                }
                link(dirfor($dest), $link) || warn "link: $!";
            }
            if ($cfg->{notify}) {
                $cfg->{notify}($link?$link:dirfor($dest), $cfg->{settings});
            }
            if ($cfg->{sync_addons}) {
                $cfg->{sync_addons}($cfg->{settings});
            }

            if ($cfg->{settings}->{_dont_register}) {
                print "not registering $cfg->{dest}\n" if $options{verbose};
            } else {
                # Save iso info for api registration
                my $settings = {%{$cfg->{settings}}};

                # clean up undefined settings - and leave empty ones
                for my $key (keys %$settings) {
                    if (!defined $settings->{$key}) {
                        delete $settings->{$key};
                    }
                }

                if ($cfg->{compute_register}) {
                    push @toregister, $cfg->{compute_register}($settings);
                } else {
                    push @toregister, $settings;
                }
            }
        }
    }

    print "registering ...\n" if $options{verbose} && @toregister;

    # Register isos
    while (my $isoinfo = shift @toregister) {

        # Compatibility with the default behavior of scheduling ISO
        $isoinfo->{_OBSOLETE} = 1;

        if ($options{"no-obsolete"}) {
            print "'no-obsolete' selected, setting '_NOOBSOLETEBUILD'\n" if $options{verbose};
            $isoinfo->{_NOOBSOLETEBUILD} = 1;
            delete $isoinfo->{_OBSOLETE};
        }
        if ($options{"deprioritize-or-cancel"}) {
            print "'deprioritizing or cancelling currently running jobs (if any), setting '_DEPRIORITIZEBUILD'\n" if $options{verbose};
            $isoinfo->{_DEPRIORITIZEBUILD} = 1;
            $isoinfo->{_DEPRIORITIZE_LIMIT} = $options{"deprioritize-limit"};
            delete $isoinfo->{_OBSOLETE};
        }
        delete $isoinfo->{'.addonsyncinfo'};

        if ($isoinfo->{ISO} || $isoinfo->{HDD_1}) {
            # get the checksum of iso/hdd
            my $asset = dirfor($isoinfo->{ISO}//$isoinfo->{HDD_1});
            if (-e $asset) {
                my $checksum_sha256 = digest_file_hex($asset, "SHA-256");
                my $ext = defined($isoinfo->{ISO}) ? 'ISO' : 'HDD_1';
                my $checksum_key = "CHECKSUM_$ext";
                $isoinfo->{$checksum_key} = $checksum_sha256;
            }
            else {
                warn "File $asset not found, checksum won't be calculated and set";
            }
            if (!dryrun()) {
                my $fn = sprintf "%s.%d.json", dirfor($asset), scalar @toregister;
                if (open my $fh, '>', $fn) {
                    print $fh to_json($isoinfo, {pretty => 1, canonical => 1});
                    close $fh;
                }
            }
        }

        if (dryrun() || $options{verbose}) {
            print to_json ($isoinfo, {pretty => 1, canonical => 1});
            next if dryrun();
        }

        if ($options{"no-trigger"}) {
            print "Option 'no-trigger' specified, skipping trigger step\n";
            next;
        }
        if (!$client) {
            print STDERR "no client found/specified, skipping trigger step\n";
            next;
        }

        my $ua_url = $openqa_url->clone();
        $ua_url->path("/api/v1/isos");
        $ua_url->query($isoinfo);
        $ua_url->query->merge(async => 1);
        my $retry_count = 0;
        while ($retry_count < $openqa_post_retry_count) {
            my $res = $client->post($ua_url)->res;
            if (!$res->is_success) {
                print STDERR "error scheduling $isoinfo->{ISO}\n";
                if ($res->code) {
                    print STDERR $res->code." ".$res->message."\n";
                    if ($res->body_size) {
                        print STDERR pp($res->json || $res->body);
                    }
                    # abort unless server side error
                    last unless $res->is_server_error;
                }
                $retry_count++;
                print STDERR "retry \# $retry_count in $openqa_post_retry_timeout_seconds s ...\n";
                sleep $openqa_post_retry_timeout_seconds;
                next;
            }
            if ($res->body_size && $options{verbose}) {
                dd($res->json || $res->body);
            }
            last;
        }
    }
}

# vim: sw=4 et

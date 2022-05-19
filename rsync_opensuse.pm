# Copyright SUSE LLC
# SPDX-License-Identifier: MIT

# File contains helper functions and variables related to openSUSE only
package rsync_opensuse;
use strict;
use warnings 'FATAL';
use Data::Dump 'dd';
use File::Basename 'basename';
use feature "state";

our $backend_opensuse = 'rsync://openqa@obs-backend.publish.opensuse.org/opensuse-internal/build/';
our $backend_opensuse2 = 'rsync://openqa@obs-back-stage.publish.opensuse.org/opensuse-internal/build/';
my $backend_opensuse_home = 'rsync://openqa@obs-back-home.publish.opensuse.org/opensuse-internal/build/';
my $opensuse_pattern = qr/^(?:openSUSE|Leap)-(?<version>[0-9.]+)-(?<arch>(?:i[56]86|x86_64|i586-x86_64|ppc64le|ppc64[-_]ppc64le|aarch64|armv7hl|s390x))-Build(?<build>[\d.]+)$/;
my $opensuse_pattern_leap_non_oss = qr/^(?:openSUSE-)?Leap-(?<version>[0-9.]+)-Addon-NonOss-FTP-(?<arch>(?:i[56]86|x86_64|i586-x86_64|ppc64le|ppc64[-_]ppc64le|aarch64|s390x))-Build(?<build>[\d.]+)$/;

sub set_config {
    $rsync::config->{staging_core} = { # re-use name to avoid having to adjust iso parser
        skip => 0,
        path =>  "$rsync_opensuse::backend_opensuse2/openSUSE:Factory:Rings:1-MinimalX/images/",
        filter => [ '+ /ppc64le', '+ /x86_64', '+ /i586', '+ /*/Test-DVD-*', '+ *.iso', '- *' ],
        rename => sub { rename_stage(shift, 'Core')},
        settings => sub { settings_stage(shift, 'Core')},
    };
    $rsync::config->{dvd} = {
       skip => 1,
       path => "$rsync_opensuse::backend_opensuse/openSUSE:Factory/images/local/",
       filter => [
           '+ /*product:*',
           '+ /*product:*/*Media*/',
           '- *Addon*',
           '- *-NET-*', # exclude NET for now as it's rebuild too often
#          '- *-Live-*', # exclude Live for now as it's rebuild too often
           '+ **/*.iso',
           '- *' ],
       settings => sub { settings_factory(shift, 'Factory'); },
    };
    $rsync::config->{tumbleweed_arm} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Factory:ARM:ToTest/",
        filter => [
            '+ /*',
            '+ /images/*',
            '+ /images/local/*product:*',
            '+ **/*.iso',
            '+ /images/aarch64/',
            '+ /images/aarch64/livecd-*/',
            '+ /images/aarch64/*JeOS*',
            # Match the directory as well to not grab efi-pxe (same filename)
            '+ *JeOS-efi.aarch64/openSUSE-Tumbleweed-*JeOS-efi.aarch64-*.raw.xz',
            '+ /images/armv7l/',
            '+ /images/armv7l/*JeOS*',
            '+ *JeOS-efi-pxe/openSUSE-Tumbleweed-*JeOS-efi.armv7l-*.raw.xz',
            '+ /appliances/aarch64/',
            '+ /appliances/*/*vagrant*/',
            '+ */Tumbleweed.aarch64-*.box',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, 'Tumbleweed') ); },
        # arm doesn't have snapshot version yet
        reposync => \&reposync_tumbleweed,
        notify => \&save_changelogs,
    };
    $rsync::config->{tumbleweed_s390x} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Factory:zSystems:ToTest/images/",
        filter => [
            '+ /*',
            # to extract iso later
            '+ /local/*product:*dvd*',
            '+ **/*.iso',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, 'Tumbleweed') ); },
        reposync => \&reposync_tumbleweed,
    };
    $rsync::config->{tumbleweed_ppc64} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Factory:PowerPC:ToTest/images/",
        filter => [
            '+ /*',
            '+ /local/*product:*ppc64*',
            '+ **/*.iso',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, 'Tumbleweed') ); },
        reposync => \&reposync_tumbleweed,
    };
    $rsync::config->{tumbleweed} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Factory:ToTest/",
        filter => [
            '+ /*',
            '+ /images/*',
            '+ /images/*/livecd-*',
            '+ /images/local/*product:*',
            '+ /images/**/*.iso',
            '+ /appliances/*',
            '+ /appliances/*/*JeOS*/',
            '+ */openSUSE-Tumbleweed-*JeOS.x86_64-*-kvm-and-xen-*.qcow2*',
            '+ /appliances/*/*vagrant*/',
            '+ */Tumbleweed.x86_64-*.box',
            '+ /appliances/*/*openSUSE-MicroOS:ContainerHost-kvm-and-xen*/',
            '+ /appliances/*/*openSUSE-MicroOS:Kubic-kubeadm-kvm-and-xen*/',
            '+ */openSUSE-MicroOS.x86_64-*-kvm-and-xen-*.qcow2',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, 'Tumbleweed') ); },
        notify => \&save_changelogs,
        reposync => \&reposync_tumbleweed,
    };
    $rsync::config->{'15_images'} = {
        skip => 1,
        path => "$backend_opensuse/openSUSE:Leap:15.0:Images:ToTest/images/",
        filter => [
            '+ /x86_64/',
            '+ /x86_64/livecd-*/',
            '+ /x86_64/*JeOS*/',
            '+ */openSUSE-Leap-15.0-*JeOS.x86_64-*-kvm-and-xen-*.qcow2',
            '+ */openSUSE-Leap-15.0-*-Media.iso',
            '- *' ],
        settings => \&settings_images,
    };
    $rsync::config->{'15.1_images'} = {
        skip => 1,
        path => "$backend_opensuse/openSUSE:Leap:15.1:Images:ToTest/images/",
        filter => [
            '+ /x86_64/',
            '+ /x86_64/livecd-*/',
            '+ /x86_64/*JeOS*/',
            '+ */openSUSE-Leap-15.1-*JeOS.x86_64-*-kvm-and-xen-*.qcow2*',
            '+ */openSUSE-Leap-15.1-*-Media.iso',
            '- *' ],
        settings => \&settings_images,
    };
    $rsync::config->{'15.1_arm_images'} = {
        skip => 1,
        path => "$backend_opensuse/openSUSE:Leap:15.1:ARM:Images:ToTest/images/",
        filter => [
            '+ /aarch64/',
            '+ /aarch64/*JeOS*',
            # Match the directory as well to not grab efi-pxe (same filename)
            '+ *JeOS-efi.aarch64/openSUSE-Leap*15.1-*JeOS-efi.aarch64-*.raw.xz',
            '- *' ],
        settings => \&settings_images,
    };
    $rsync::config->{'15.2'} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Leap:15.2:ToTest/images/",
        filter => [
            '+ /*',
            '+ /local/*product:*',
            '+ **/*-DVD-*.iso',
            '+ **/*-NET-*.iso',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, '15.2') ); },
        notify => \&save_changelogs,
        reposync => \&reposync_leap,
    };
    $rsync::config->{'15.2_images'} = {
        skip => 1,
        path => "$backend_opensuse/openSUSE:Leap:15.2:Images:ToTest/images/",
        filter => [
            '+ /x86_64/',
            '+ /x86_64/livecd-*/',
            '+ /x86_64/*JeOS*/',
            '+ */openSUSE-Leap-15.2-*JeOS.x86_64-*-kvm-and-xen-*.qcow2*',
            '+ */openSUSE-Leap-15.2-*-Media.iso',
            '+ /x86_64/*vagrant*/',
            '+ */Leap-15.2.x86_64-*.box',
            '- *' ],
        settings => \&settings_images,
    };
    $rsync::config->{'15.2_arm'} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Leap:15.2:ARM:ToTest/",
        filter => [
            '+ /images',
            '+ /images/local',
            '+ /images/local/*product:*',
            '+ **/*-DVD-*.iso',
            '+ **/*-NET-*.iso',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, '15.2') ); },
        reposync => \&reposync_leap,
    };
    $rsync::config->{'15.2_arm_images'} = {
        skip => 1,
        path => "$backend_opensuse/openSUSE:Leap:15.2:ARM:Images:ToTest/images/",
        filter => [
            '+ /aarch64/',
            '+ /aarch64/livecd-*/',
            '+ /aarch64/*JeOS*',
            '+ */openSUSE-Leap-15.2-*-Media.iso',
            # Match the directory as well to not grab efi-pxe (same filename)
            '+ *JeOS-efi.aarch64/openSUSE-Leap*15.2-*JeOS-efi.aarch64-*.raw.xz',
            '+ /aarch64/*vagrant*/',
            '+ */Leap-15.2.aarch64-*.box',
            '- *' ],
        settings => \&settings_images,
    };
    $rsync::config->{'15.2_ppc'} = {
        skip => 0,
        path => "$backend_opensuse/openSUSE:Leap:15.2:PowerPC:ToTest/",
        filter => [
            '+ /images',
            '+ /images/local',
            '+ /images/local/*product:*',
            '+ **/*-DVD-*.iso',
            '+ **/*-NET-*.iso',
            '- *' ],
        settings => sub { add_repo_factory( settings_factory(shift, '15.2') ); },
        reposync => \&reposync_leap,
    };
    $rsync::config->{'15.2_core'} = {
        skip => 0,
        path =>  "$backend_opensuse2/openSUSE:Leap:15.2:Rings:1-MinimalX/images/",
        filter => [ '+ /ppc64le', '+ /x86_64', '+ /i586', '+ /*/000product:*', '+ *.iso', '- *' ],
        rename => sub { rename_stage(shift, 'Core', undef, ':15')},
        settings => sub { settings_stage(shift, '15.2:Core')},
    };
    $rsync::config->{staging} = {
        skip => 0,
        path => $rsync_opensuse::backend_opensuse2,
        filter => [
            '+ /openSUSE:Factory:Staging:*',
            '+ /openSUSE:Factory:Staging:*/images',
            '+ /openSUSE:Factory:Staging:*/images/x86_64',
            '+ /openSUSE:Factory:Staging:*/images/x86_64/000product:openSUSE-dvd5-dvd-x86_64',
            '+ /openSUSE:Factory:Staging:*/images/x86_64/000product:openSUSE-Tumbleweed-Kubic-dvd5-dvd-x86_64',
            '+ /openSUSE:Factory:Staging:*/images/x86_64/000product:openSUSE-MicroOS-dvd5-dvd-x86_64',
            '+ /openSUSE:Factory:Staging:*/images/x86_64/000product:openSUSE-MicroOS-dvd5-kubic-dvd-x86_64',
            '+ *.iso',
            '- *',
        ],
        rename => sub {
            $_[1] =~ /^openSUSE:Factory:Staging:([[:alnum:]:]*)\//;
            rename_stage($_[0], $1);
        },
        settings => sub {
            $_[1] =~ /^openSUSE:Factory:Staging:([[:alnum:]:]*)\//;
            settings_stage($_[0], "Staging:$1");
        },
    };
    $rsync::config->{staging_15} = {
        skip => 0,
        path => $rsync_opensuse::backend_opensuse2,
        filter => [
            '+ /openSUSE:Leap:15.2:Staging:*',
            '+ /openSUSE:Leap:15.2:Staging:*/images',
            '+ /openSUSE:Leap:15.2:Staging:*/images/x86_64',
            '+ /openSUSE:Leap:15.2:Staging:*/images/x86_64/000product:openSUSE-dvd5-dvd-x86_64',
            '+ /openSUSE:Leap:15.2:Staging:*/images/x86_64/000product:Leap-dvd5-dvd-x86_64',
            '+ *.iso',
            '- *',
        ],
        rename => sub {
            $_[1] =~ /^openSUSE:Leap:15.2:Staging:([[:alnum:]:]*)\//;
            rename_stage_15($_[0], $1);
        },
        settings => sub {
            $_[1] =~ /^openSUSE:Leap:15.2:Staging:([[:alnum:]:]*)\//;
            settings_stage_15($_[0], "15.2:S:$1");
        },
    };
}

sub settings_images {
    my ($file) = @_;

    return settings_jeos(@_) if $file !~ /\.iso$/;

    return undef unless ($file =~ /^openSUSE-(?:Factory|Leap)-(?<version>[^-]+)-(?<flavor>.+)-(?<arch>(?:i[56]86|x86_64|i586-x86_64|ppc64|ppc64le|aarch64|s390x))-(?:Snapshot|Build)(?<build>[^-]+)-Media\.iso$/);

    return {
      DISTRI => 'opensuse',
      VERSION => $+{version},
      FLAVOR  => $+{flavor},
      ARCH    => $+{arch},
      BUILD   => $+{build},
    };
}

sub rename_stage_15 {
    my $name = shift;
    my $stage = shift;
    my $prj = 'Staging';
    if ($name =~ /.*-Build([^-]+)-Media.iso/) {
        return sprintf("openSUSE-Leap:15.2-Staging:%s-%s-DVD-x86_64-Build%s-Media.iso", $stage, $prj, $1);
    }
}

sub settings_stage_15 {
    my ($name, $version) = @_;
    my $prj = 'Staging';
    my $stage = $version;
    $stage =~ s,S:,,;
    if ($name =~ /.*-Build([^-]+)-Media.iso/) {
        return {
            DISTRI => 'opensuse',
            VERSION => $version,
            ARCH => 'x86_64',
            FLAVOR => $prj.'-DVD',
            BUILD => $1,
        };
    }
    return undef;
}

sub settings_stage {
    my ($name, $version, $arch) = @_;
    $arch //= 'x86_64';
    my $prj = 'Staging';
    my $stage = $version;
    $stage =~ s,Staging:,,;
    if ($name =~ /.*Kubic.*-Build([^-]+)-Media.iso/) {
        return {
            DISTRI => 'microos',
            VERSION => $version,
            ARCH => $arch,
            FLAVOR => $prj.'-Kubic-DVD',
            BUILD => $1,
        };
    }
    elsif ($name =~ /.*MicroOS.*-Build([^-]+)-Media.iso/) {
        return {
            DISTRI => 'microos',
            VERSION => $version,
            ARCH => $arch,
            FLAVOR => $prj.'-DVD',
            BUILD => $1,
        };
    }
    elsif ($name =~ /.*-Build([^-]+)-Media.iso/) {
        return {
            DISTRI => 'opensuse',
            VERSION => $version,
            ARCH => $arch,
            FLAVOR => $prj.'-DVD',
            BUILD => $1,
        };
    }
    return undef;
}

sub rename_stage {
    my $name = shift;
    my $stage = shift;
    my $arch = shift || 'x86_64';
    my $name_suffix = shift // '';
    if ($name =~ /.*Kubic.*-Build([^-]+)-Media.iso/) {
        return sprintf("openSUSE$name_suffix-Staging:%s-Kubic-DVD-%s-Build%s-Media.iso", $stage, $arch, $1);
    }
    elsif ($name =~ /.*MicroOS.*-Build([^-]+)-Media.iso/) {
        return sprintf("openSUSE$name_suffix-Staging:%s-MicroOS-DVD-%s-Build%s-Media.iso", $stage, $arch, $1);
    }
    elsif ($name =~ /.*-Build([^-]+)-Media.iso/) {
        return sprintf("openSUSE$name_suffix-Staging:%s-Tumbleweed-DVD-%s-Build%s-Media.iso", $stage, $arch, $1);
    }
}

sub mirror_opensuse_factory {
    my $settings = shift;
    # we need a http URL here - NET installs are HTTP only (we don't test SMB or FTP)
    $settings->{MIRROR_PREFIX} = $rsync::options{repourl};
    $settings->{SUSEMIRROR}    = $rsync::options{repourl}."/".$settings->{REPO_0};
    $settings->{MIRROR_HTTP}   = $settings->{SUSEMIRROR};
    $settings->{MIRROR_HTTPS}  = $settings->{MIRROR_HTTP} =~ s|http://|https://|r;
    $settings->{FULLURL} = 1;
}

sub settings_factory {
    my ($file, $version) = @_;
    return settings_microos_images(@_) if $file =~ /^openSUSE-MicroOS.+\.qcow2$/;
    return settings_jeos(@_) if $file !~ /\.iso$/;
    return undef unless ($file =~ /^openSUSE-(?:Factory|Tumbleweed|Kubic|MicroOS|13\.2|Leap-[0-9]*.[0-9])-(?<flavor>.+?)-(?<arch>(?:i[56]86|x86_64|i586-x86_64|ppc64|ppc64le|aarch64|s390x))-(?:Snapshot|Build)(?<build>[^-]+)-Media\.iso$/);
    my $settings = {
        DISTRI => 'opensuse',
        VERSION => $version,
        FLAVOR => $+{flavor},
        ARCH => $+{arch},
        BUILD => $+{build},
    };
    $settings->{DISTRI} = 'microos' if $file =~ /(?:Kubic|MicroOS)/;
    $settings->{FLAVOR} = 'Kubic-DVD' if $file =~ /Kubic/;
    return $settings;
}

sub settings_jeos {
    my ($file) = @_;

    return {} if $file =~ /\.box$/; # The .box is just synced but doesn't trigger jobs itself

    my $settings = { ISO => ''};
    my $pattern = '(:?Leap-)?(?<version>[^-]+)(?:-.*-.*)?-JeOS\.(?<arch>[^-]+)-(?:[^-]+)-(?<flavor>kvm-and-xen|MS-HyperV|OpenStack-Cloud|VMware|XEN)-(?:Snapshot|Build)(?<build>[^-]+)\.(?:qcow2|vmdk|vhdx)(?:\.xz)?';
    my $pattern_arm = '(:?Leap-)?(?<version>[^-]+)-(?:ARM-)?JeOS(?:-.*)?\.(?<arch>[^-]+)-[^-]*-(?:Snapshot|Build)(?<build>[^-]+)\.raw\.xz';

    if ($file =~ /^openSUSE-$pattern/) {
        $settings->{FLAVOR} = 'JeOS-for-' . $+{flavor};
    }
    elsif ($file =~ /^openSUSE-$pattern_arm/) {
        $settings->{FLAVOR} = 'JeOS-for-AArch64';
    }
    else {
        return undef;
    }

    $settings->{DISTRI} = 'opensuse';
    $settings->{VERSION} = $+{version};
    $settings->{ARCH} = $+{arch};
    $settings->{BUILD} = $+{build};
    $settings->{HDD_1} = $file;

    $settings->{ARCH} = "armv7hl" if $settings->{ARCH} eq "armv7l";

    return $settings;
}

sub settings_microos_images {
    my ($file) = @_;

    if ($file !~ /^openSUSE-MicroOS.(?<arch>[^-]+)-[0-9.]+-(?<flavor>.+)-kvm-and-xen-Snapshot(?<build>[^-]+)\.qcow2$/) {
        return undef;
    }

    my $settings = { ISO => '', VERSION => 'Tumbleweed' };
    $settings->{DISTRI} = 'microos';
    $settings->{FLAVOR} = 'MicroOS-Image-' . $+{flavor};
    $settings->{ARCH} = $+{arch};
    $settings->{BUILD} = $+{build};
    $settings->{HDD_1} = $file;

    return $settings;
}

sub save_changelogs {
    my ($filename, $settings) = @_;
    use FindBin;
    my $script = $FindBin::Bin.'/factory-package-news.py';
    return unless -x $script;
    return unless my $flavor = $settings->{FLAVOR};
    return unless my $arch = $settings->{ARCH};
    return unless ($flavor =~ /DVD|Kubic-DVD/ && $arch =~ /x86_64|aarch64/);
    my $distri = ($flavor eq 'Kubic-DVD') ? 'kubic' : $settings->{DISTRI};
    die "Missing distri" unless $distri;
    my $suffix = ($arch eq 'x86_64') ? '' : "-$arch";
    my $version = $settings->{VERSION};
    die "Missing version" unless $version;
    my $dir = sprintf "/var/lib/snapshot-changes/%s%s/%s", $distri, $suffix, $version;
    my @cmd = ($script,
        'save',
        '--dir',
        $dir,
        '--snapshot',
        $settings->{BUILD}, $filename);
    dd \@cmd if $rsync::options{'verbose'};
    system(@cmd);
}

# For Tumbleweed some architectures are mapped to other strings in urls
sub factory_get_url_arch {
    my $arch = shift;
    return 'i586-x86_64' if ($arch eq 'x86_64' || $arch =~ /^i\d86$/);
    return 'ppc64_ppc64le' if ($arch eq 'ppc64' || $arch eq 'ppc64le');
    return $arch;
}

sub add_repo_factory {
    my $settings = shift;
    return undef unless $settings;
    return $settings unless defined $settings->{ARCH};
    my $arch = factory_get_url_arch($settings->{ARCH});

    $settings->{REPO_0} = sprintf "openSUSE-%s-oss-$arch-Snapshot%s", $settings->{VERSION}, $settings->{BUILD};
    $settings->{REPO_OSS} = $settings->{REPO_0};
    $settings->{REPO_1} = sprintf "openSUSE-%s-oss-$arch-Snapshot%s-debuginfo", $settings->{VERSION}, $settings->{BUILD};
    $settings->{REPO_OSS_DEBUGINFO} = $settings->{REPO_1};
    # Sync parts of the oss source repo
    $settings->{REPO_3} = sprintf "openSUSE-%s-oss-$arch-Snapshot%s-source", $settings->{VERSION}, $settings->{BUILD};
    $settings->{REPO_OSS_SOURCE} = $settings->{REPO_3};
    # Comma separated list of the packages to be synced if do not want to sync full repo
    # Set list of packages which are synced for repo, so can be crosschecked in the test
    $settings->{REPO_OSS_SOURCE_PACKAGES} = 'coreutils,yast2-network*';
    # kernel debug packages are used in kdump
    # java* and mraa-debug* packages are used in java test module    
    $settings->{REPO_OSS_DEBUGINFO_PACKAGES} = 'java*,kernel-default-debug*,kernel-default-base-debug*,mraa-debug*';
    if($settings->{ARCH} eq 'x86_64') {
        # Sync non-oss for x86_64 only
        $settings->{REPO_2} = sprintf "openSUSE-%s-non-oss-$arch-Snapshot%s", $settings->{VERSION}, $settings->{BUILD};
        $settings->{REPO_NON_OSS} = $settings->{REPO_2};
    }
    mirror_opensuse_factory($settings),
    return $settings;
}

# Form location of the repo for openSUSE, this is complex logic which we can fix only by
# using more clean structure on obs itself
sub get_repo_location {
    my (%args) = @_;
    my $location = $args{prefix}; # init with prefix
    $location .= 'images/' if ($location =~ /:ToTest\/$/);

    if ($args{factory}) { # Build location for TW
        my $arch = factory_get_url_arch($args{arch});

        if ($args{oss}) {
            $location .= '/local/*product:openSUSE-ftp-ftp';
        } elsif ($args{non_oss}) {
            $location .= '/local/*product:openSUSE-Addon-NonOss-ftp-ftp';
        }
        # x86 and ppc are inconsistent have _ or - in directories as separator
        if($args{arch} eq 'x86_64' || $args{arch} =~ /^i\d86$/) {
            $location .= "-i586_x86_64/openSUSE-*-$arch-Media1/";
        } elsif($args{arch} =~ /ppc64/) {
            $location .= "-$arch/openSUSE-*-ppc64-ppc64le-Media1/";
        } else {
            $location .= "-$arch/openSUSE-*-$arch-Media1/";
        }
    } elsif ($args{leap}) { # Build location for Leap
        if ($args{arch} =~ /ppc64/ && $args{oss}) {
            $location .= ':PowerPC:ToTest/images/local/*product:*-ftp-ftp-ppc64le/*-*-Media1/';
        } elsif ($args{arch} eq 'aarch64' && $args{oss}) {
            $location .= ':ARM:ToTest/images/local/*product:*-ftp-ftp-aarch64/*-*-Media1/';
        } else { # No s390x for leap
            if ($args{oss}) {
                $location .= "/images/local/*product:openSUSE-ftp-ftp-x86_64/*-*-Media1/";
            } elsif ($args{non_oss}) {
                $location .= "/images/local/*product:*-Addon-NonOss-ftp-ftp-x86_64/*-*-Media1/";
            }
        }
    }

    die 'Requested repo location for not defined distri, please check the settings' unless $location;

    # Replace Media1 with Media2 for debug repos
    $location =~ s/Media1/Media2/ if $args{debug};
    # Replace Media1 with Media3 for source repos
    $location =~ s/Media1/Media3/ if $args{source};
    return $location;
}

# a wrapper so we don't try repo rsync for every iso
sub reposync_tumbleweed {
    state $ret;
    return $ret if defined $ret;

    my ($cfg, $settings) = @_;
    # define which repos to sync
    my %repos = (
        $settings->{REPO_OSS} => {oss => '1', tumbleweed => '1'},
        $settings->{REPO_OSS_DEBUGINFO} => {oss => '1', debug => '1', tumbleweed => '1'},
    );
    # Sync non-oss repo if defined (syncing only for x86 ATM)
    $repos{$settings->{REPO_NON_OSS}} = {non_oss => '1', tumbleweed => '1'} if $settings->{REPO_NON_OSS};

    if ($settings->{REPO_OSS_SOURCE}) {
         # List packages for the source repo
         my $source_packages = [split(',', $settings->{REPO_OSS_SOURCE_PACKAGES})];
         $repos{$settings->{REPO_OSS_SOURCE}} = {oss => '1', tumbleweed => '1', source => '1', packages => $source_packages};
    }

    if ($settings->{REPO_OSS_DEBUGINFO}) {
         # List packages for the debug repo
         my $debug_packages = [split(',', $settings->{REPO_OSS_DEBUGINFO_PACKAGES})];
         $repos{$settings->{REPO_OSS_DEBUGINFO}} = {oss => '1', tumbleweed => '1', debug => '1', packages => $debug_packages};
    }

    while(my($repo, $opts) = each %repos)
    {
      # Skip if defined architectures do not include the one we are trying to sync
      if ($opts->{archs}) {
          next unless grep { $settings->{ARCH} eq $_ } @{$opts->{archs}};
      }
      my $location = get_repo_location( arch    => $settings->{ARCH}, # architecture
                                        prefix  => $cfg->{path},      # path prefix for the repo
                                        factory => 1,                 # use flow for factory
                                        %$opts);                      # repo specific options
      $ret = rsync::_reposync(
          location => $location,
          targetname => $repo,
          expect_buildid => $opts->{non_oss} ? undef : $settings->{BUILD}, # non-oss repos do not have valid build id on TW
          buildid_variable => 'version',
          buildid_pattern => $opensuse_pattern,
          packages => $opts->{packages},
      );
    }

    return $ret;
}

# a wrapper so we don't try repo rsync for every iso
sub reposync_leap {
    state $ret;
    return $ret if defined $ret;
    my ($cfg, $settings) = @_;

    my $version = $settings->{VERSION};

    my $location;
    my %repos = (
        $settings->{REPO_OSS} => {oss => '1'},
        $settings->{REPO_OSS_DEBUGINFO} => {oss => '1', debug => '1'},
    );
    # Sync non-oss repo if defined
    $repos{$settings->{REPO_NON_OSS}} = {non_oss => '1'} if $settings->{REPO_NON_OSS};

    if ($settings->{REPO_OSS_SOURCE}) {
         # List packages for the source repo
         my $source_packages = [split(',', $settings->{REPO_OSS_SOURCE_PACKAGES})];
         $repos{$settings->{REPO_OSS_SOURCE}} = {oss => '1', source => '1', packages => $source_packages};
    }

    if ($settings->{REPO_OSS_DEBUGINFO}) {
         # List packages for the debug repo
         my $debug_packages = [split(',', $settings->{REPO_OSS_DEBUGINFO_PACKAGES})];
         $repos{$settings->{REPO_OSS_DEBUGINFO}} = {oss => '1', debug => '1', packages => $debug_packages};
    }

    while(my($repo, $opts) = each %repos)
    {
      # Skip if defined architectures do not include the one we are trying to sync
      if ($opts->{archs}) {
          next unless grep { $settings->{ARCH} eq $_ } @{$opts->{archs}};
      }
      my $location = get_repo_location( arch   => $settings->{ARCH},                          # architecture
                                        prefix => "$backend_opensuse/openSUSE:Leap:$version", # path prefix
                                        leap   => '1',                                        # leap distri flow
                                        %$opts);                                              # repo specific settings
      $ret = rsync::_reposync(
          location => $location,
          targetname => $repo,
          expect_buildid => $settings->{BUILD},
          buildid_pattern => $opts->{non_oss} ? $opensuse_pattern_leap_non_oss : $opensuse_pattern,
          packages => $opts->{packages},
      );
    }

    return $ret;
}

sub override_methods {}

1;
# vim: sw=4 et

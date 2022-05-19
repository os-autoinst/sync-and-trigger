# Copyright SUSE LLC
# SPDX-License-Identifier: MIT

# File contains helper functions and variables related to SLE only
package rsync_sle;
use strict;
use warnings 'FATAL';
use feature "state";
use File::Basename 'basename';
use Net::FTP;
use Sub::Override;

sub set_config {
    $rsync::config->{sle15} = {
       path => "dist.suse.de::repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/TEST/images/iso/",
       sync_addons => \&rsync::sync_addons,
       compute_register => \&compute_register_sle,
       reposync => \&reposync_sle,
       filter => [
            "+ SLE-$rsync::version_in_staging-Installer-DVD-x86_64-*-Media1.iso",
            "+ SLE-$rsync::version_in_staging-Installer-DVD-ppc64le-*-Media1.iso",
            "+ SLE-$rsync::version_in_staging-Installer-DVD-s390x-*-Media1.iso",
            "+ SLE-$rsync::version_in_staging-Installer-DVD-aarch64-*-Media1.iso",
            "- *" ],
        settings => sub {
            my $fn = shift;
            if ($fn =~ /^SLE-$rsync::version_in_staging-(?<flavor>(?:Installer)-(DVD))-(?<arch>[^-]+)-Build(?<build>[^-]+)-/) {
                my $settings = {
                    DISTRI => 'SLE',
                    VERSION => "$rsync::version_in_staging",
                    FLAVOR => $+{flavor},
                    ARCH => $+{arch},
                    BUILD => $+{build},
                    BUILD_SLE => $+{build},
                };
                add_sle_addons($settings);
                mirror_sle($settings);
                return $settings;
            }
            return undef;
        },
    };
    $rsync::config->{sle15_sp1} = {
       major_version => '15',
       sp_version => 'SP1',
       mapto => 'sle15',
    };
    $rsync::config->{sle15_sp2} = {
       major_version => '15',
       sp_version => 'SP2',
       mapto => 'sle15',
    };
    $rsync::config->{sle_staging} = {
        skip => 1,
        path => "dist.suse.de::repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/Staging:/",
        filter => [
            '- /P/*',
            '+ /*',
            '+ /*/images',
            '+ /*/images/iso',
            '+ /*/images/iso/*-Server-DVD-x86_64-*-Media.iso',
            '+ /*/images/iso/*-Server-DVD-x86_64-*-Media1.iso',
            # use http repo instead
            #"+ SLE-$rsync::major_version-WE-DVD-x86_64-*-Media?.iso",
            # not bootable
            #"+ SLE-$rsync::major_version-HA-DVD-x86_64-*-Media1.iso",
            '- *' ],
        rename => sub {
            my $name = $_[0];
            # For SLE 15 we use SLE-15-Server ISOs instead of Test-Server ISOs, but we want them to be renamed appropriately
            if ($name !~ /^Test-Server/) {
                $name =~ s/.*-Server/Test-Server/;
            }
            # If Staging ISO ends in Media1.iso rename output to end in Media.iso
            $name =~ s/Media1.iso$/Media.iso/;
            if ($_[1] =~ m,^([[:alnum:]]+)/,) {
               my $letter = $1;
               # Inject Staging Letter into Build Number for Renamed Media
               $name =~ s/-Build/-Build$letter./;
               $name = "SLE$rsync::version_in_staging-Staging:$letter-$name";
            }
            return $name;
        },

        settings => sub {
            my ($fn, $path, $build) = @_;
            $path =~ s,/.*,,;
            if ($fn =~ /.*-Server-DVD-([^-]+)-Build([^-]+)-/) {
                # Inject Staging Letter into Build Number from Original Media
                $build = "$path.$2";
                return {
                    DISTRI => 'SLE',
                    VERSION => "$rsync::version_in_staging",
                    FLAVOR => "Server-DVD-$path-Staging",
                    ARCH => $1,
                    BUILD => $build
                };
            }
            return undef;
        },
    };
    $rsync::config->{sle15_staging} = {
       skip => 1,
       path => "dist.suse.de::repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/Staging:/",
       sync_addons => \&rsync::sync_addons,
       compute_register => \&compute_register_sle,
       reposync => \&reposync_sle,
       filter => [
           '+ /*',
           '+ /*/images',
           '+ /*/images/iso',
           "+ /*/images/iso/SLE-$rsync::version_in_staging-Installer-DVD-x86_64-*-Media.iso",
           "+ /*/images/iso/SLE-$rsync::version_in_staging-Installer-DVD-x86_64-*-Media1.iso",
           '- *'],
        rename => sub {
            my $name = $_[0];
            if ($_[1] =~ m,^([[:alnum:]]+)/,) {
               my $letter = $1;
               # Inject Staging Letter into Build Number for Renamed Media
               $name = rsync::rename_for_staging_sync($name, $letter);
            }
            return $name;
        },
        settings => sub {
            my ($fn, $path, $build) = @_;
            (my $staging_letter = $path) =~ s,/.*,,;
            if ($fn =~ /^SLE-$rsync::version_in_staging-(?<flavor>(?:Installer)-(DVD))-(?<arch>[^-]+)-Build(?<build>[^-]+)-/) {
                $build = "$staging_letter." . $+{build};
                my $settings = {
                    DISTRI => 'SLE',
                    VERSION => "$rsync::version_in_staging",
                    FLAVOR => $+{flavor} . "-$staging_letter-Staging",
                    ARCH => $+{arch},
                    BUILD => $build,
                    BUILD_SLE => $build,
                    STAGING => $staging_letter
                };
                add_sle_addons($settings);
                return $settings;
            }
            return undef;
        },
    };
    $rsync::config->{sle15_staging_a} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'A',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_b} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'B',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_c} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'C',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_d} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'D',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_e} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'E',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_f} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'F',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_g} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'G',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_h} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'H',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_s} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'S',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_v} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'V',
        sp_version => 'SP2',
    };
    $rsync::config->{sle15_staging_y} = {
        mapto => 'sle15_staging',
        major_version => '15',
        staging_letter => 'Y',
        sp_version => 'SP2',
    };
    $rsync::config->{sle_staging_s390} = {
        skip => 1,
        path => "dist.suse.de::repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/Staging:/S390:/",
        filter => [
            '+ /*',
            '+ /*/images',
            '+ /*/images/iso',
            '+ /*/images/iso/Test-Server-DVD-s390x-*-Media.iso',
            '- *' ],
        rename => sub {
            my $name = $_[0];
            if ($_[1] =~ m,^([[:alnum:]]+)/,) {
               my $letter = $1;
               # the s390 repo needs special treatment
               $name =~ s,-Test-Server-DVD,,;
               $name =~ s,-Media,,;
               $name = "SLE$rsync::version_in_staging-Staging-$letter-$name";
            }
            return $name;
        },
        sync_addons => \&register_staging_s390,
        settings => sub {
            my ($fn, $path) = @_;
            $path =~ s,/.*,,;
            if ($fn =~ /^Test-Server-DVD-([^-]+)-Build([^-]+)-/) {
                return {
                    DISTRI => 'SLE',
                    VERSION => "$rsync::version_in_staging",
                    FLAVOR => "Server-DVD-Staging:$path",
                    ARCH => $1,
                    BUILD => $2
                };
            }
            return undef;
        },
    };
    $rsync::config->{sle12_sp4_rt} = {
        major_version => '12',
        sp_version => 'SP4',
        skip => 1,
        path => "rsync://dist.suse.de/repos/Devel:/RTE:/SLE12SP4/",
        filter => [
            '+ images/iso/SLE-12-SP4-RT-DVD-x86_64-Build*-Media1.iso',
            '- images/iso/SLE-12-SP4-RT-DVD-x86_64-Build*-Media2.iso' ],
        sync_addons => \&rsync::sync_addons,
        reposync => \&reposync_sle,
        settings => sub {
            my $fn = shift;
            if ($fn =~ /^SLE-12-SP4-RT-DVD-([^-]+)-Build([^-]+)-/) {
                my $settings = {
                    DISTRI => 'SLE',
                    VERSION => '12-SP4',
                    FLAVOR => 'Server-DVD-RT',
                    ARCH => $1,
                    BUILD_RT => $2,
                    BUILD => $2,
                    BUILD_SLE => 'GM',
                    ISO => 'SLE-12-SP4-Server-DVD-x86_64-GM-DVD1.iso',
                };
                add_sle_addons($settings);
                return $settings;
            }
            return undef;
        },
    };
    $rsync::config->{sle12sp5_wsl} = {
       major_version => '12',
       sp_version => 'SP5',
       mapto => 'sle_wsl',
    };
    $rsync::config->{sle_wsl} = {
        skip => 1,
        path => "dist.suse.de::repos/Virtualization:/WSL/SLE_12_SP5/",
        sync_addons => \&rsync::sync_addons,
        reposync => \&reposync_sle,
        filter => [
            "+ SUSE-Linux-Enterprise-Server-$rsync::version_in_staging-*.appx",
            '- *' ],
        settings => sub {
            my $fn = shift;
            if ($fn =~ /^SUSE-Linux-Enterprise-(?<flavor>Server)-$rsync::version_in_staging-x64-Build(?<build>[^-]+).appx/) {
                my $settings = {
                    DISTRI => 'SLE',
                    VERSION => "$rsync::version_in_staging",
                    FLAVOR => $+{flavor},
                    ARCH => 'x86_64',
                    BUILD => $+{build},
                    BUILD_SLE => $+{build},
                    ASSET_1 => $fn,
                };
                my $product = $+{flavor};
                add_sle_addons($settings);
                return $settings;
            }
            return undef;
        }
    };
    $rsync::config->{sle_jeos} = {
        skip => 1,
        path => "dist.suse.de::repos/SUSE:/SLE-$rsync::major_version:/Update:/JeOS/images/",
        filter => [
            "+ SLES$rsync::major_version-JeOS-for-kvm-and-xen.x86_64-*.qcow2",
            '- *' ],
        settings => sub {
            my $fn = shift;
            if ($fn =~ /^SLES$rsync::major_version-(?<flavor>JeOS-for-(?:kvm-and-xen|MS-HyperV|OpenStack-Cloud|VMware|XEN))\.(?<arch>[^-]+)-(?<version>[^-]+)-Build(?<build>[^-]+)\.qcow2/) {
                return {
                    DISTRI => 'SLE',
                    VERSION => $rsync::major_version,
                    FLAVOR => $+{flavor},
                    ARCH => $+{arch},
                    BUILD => $+{build},
                    ISO => '',
                    HDD_1 => $fn,
                };
            }
            return undef;
        },
    };
    $rsync::config->{sle15_sp2_jeos} = {
        skip => 1,
        path => "dist.suse.de::repos/SUSE:/SLE-15-SP2:/GA:/TEST/images/",
        filter => [
            '+ SLES15-SP2-JeOS.x86_64-15.2-kvm-and-xen-*.qcow2',
            '+ SLES15-SP2-JeOS.x86_64-15.2-XEN-*.qcow2',
            '+ SLES15-SP2-JeOS.x86_64-15.2-MS-HyperV-*.vhdx.xz',
            '+ SLES15-SP2-JeOS.aarch64-15.2-RaspberryPi-*.raw.xz',
            '- *' ],
        settings => \&settings_jeos
    };
    $rsync::config->{sle_core} = {
        skip => 1,
        path => "dist.suse.de::repos/SUSE:/SLE-$rsync::major_version:/Rings:/1-MinimalX/images/iso/",
        filter => [
            '+ *.iso',
            '- *' ],
        rename => sub {
            my $name = shift;
            if ($name =~ /Test-Build([^-]+)-Media.iso/) {
                return sprintf("SLE-$rsync::major_version-Core-DVD-x86_64-Build%s-Media.iso", $1);
            }
        },
        settings => sub {
            my $fn = shift;
            if ($fn =~ /^Test-Build([^-]+)/) {
                return {
                    DISTRI => 'SLE',
                    VERSION => $rsync::major_version,
                    FLAVOR => 'Core-DVD',
                    ARCH => 'x86_64',
                    BUILD => $1,
                };
            }
            return undef;
        },
    };
    $rsync::config->{vmdp_stable} = {
        skip => 1,
        path => 'xen100.virt.lab.novell.com::VMDP/release/',
        filter => [
            '+ /*',
            '+ VMDP-WIN*.iso',
            '- *',
            ],
            settings => sub { settings_vmdp(shift, 'stable'); },
    };
    $rsync::config->{vmdp_testing} = {
        skip   => 1,
        path   => 'xen100.virt.lab.novell.com::VMDP/testing/current/',
        filter => [
            '+ *.iso',
            '- *',
        ],
        settings => sub { settings_vmdp(shift, 'testing'); },
    };
    $rsync::config->{ses_5_dev} = {
        skip   => 1,
        path   => "dist.suse.de::repos/Devel:/Storage:/5.0/images/iso/",
        filter => [
            '+ SUSE-Enterprise-Storage-?-DVD-x86_64-*-Media1.iso',
            '- *'],
        settings => \&settings_ses
    };
    $rsync::config->{ses_6_dev} = {
        skip   => 1,
        path   => "dist.suse.de::repos/Devel:/Storage:/6.0/images/iso/",
        filter => [
            '+ SUSE-Enterprise-Storage-?-DVD-x86_64-*-Media1.iso',
            '- *'],
        settings => \&settings_ses
    };
}

sub ensure_scc_valid_entry {
    my $entry = shift;
    # Put server and desktop in uppercase only if it's pool
    # Server|Desktop -> SERVER|DESKTOP, see bsc#980867
    $entry =~ s/(?<!Transactional-)(Server|Desktop)-POOL/\U$1\E-POOL/;
    return $entry;
}

sub settings_ses {
    my ($file) = @_;
    my $settings = { ADDONS => 'ses' };
    $settings->{DISTRI} = 'sle';
    if ($file =~ /^SUSE-Enterprise-Storage-(\d)-(?<flavor>[^\.]+)-(?<arch>[^-]+)-Build(?<build>[^-]+)-Media1.iso/) {
        $settings->{ISO_1} = $file;
    }
    if ($1 eq '5') {
        $settings->{VERSION} = '12-SP3';
        $settings->{ISO} = 'SLE-12-SP3-Server-DVD-x86_64-GM-DVD1.iso';
        $settings->{FLAVOR} = 'Server-DVD-SES';
    } else {
        $settings->{VERSION} = '15-SP1';
        $settings->{ISO} = 'SLE-15-SP1-Installer-DVD-x86_64-CURRENT-Media1.iso';
        $settings->{FLAVOR} = 'Installer-DVD-SES';
    }
    $settings->{ARCH} = $+{arch};
    $settings->{BUILD_SES} = $+{build};
    return $settings;
}

sub settings_vmdp {
    my ($file, $version) = @_;
    return undef unless ($file =~ /^(?:VMDP-WIN|vmdp)-(?<build>.*?)_(?:vblk|virtio).iso$/);
    return {
        DISTRI  => 'vmdp',
        VERSION => $version,
        FLAVOR  => 'standard',
        ARCH    => 'x86_64',
        BUILD   => $+{build},
        ISO     => '',           # will be removed later
        ISO_1   => $file,
        ADDONS  => 1,
    };
}

sub settings_jeos {
    my ($file) = @_;
    my $settings = { ISO => ''};
    my $pattern = '(?<version>(?!-JeOS).*)-JeOS\.(?<arch>[^-]+)-(?<version>[^-]+)-(?<flavor>kvm-and-xen|MS-HyperV|OpenStack-Cloud|VMware|XEN|RaspberryPi)-Build(?<build>[^-]+)\.(?:qcow2|qcow2\.xz|vmdk|vhdx|vhdx\.xz|raw\.xz)';
    $settings->{HDD_1} = $file;
    $settings->{DISTRI} = 'sle' if $file =~ /^SLES$pattern/;
    $settings->{VERSION} = $+{version};
    $settings->{FLAVOR} = 'JeOS-for-' . $+{flavor};
    $settings->{ARCH} = $+{arch};
    $settings->{BUILD} = $+{build};
    return $settings;
}

# Add mirrors for network installation tests
sub mirror_sle {
    my $settings = shift;
    my $flavor = shift // $settings->{FLAVOR}; # Override for MINI-ISO
    my $sle_path = sprintf "SLE-%s-%s-%s-Build%s-Media1",
                            $settings->{VERSION},
                            $flavor,
                            $settings->{ARCH},
                            $settings->{BUILD};

    $settings->{MIRROR_HTTP}  = "http://openqa.suse.de/assets/repo/$sle_path";
    $settings->{MIRROR_HTTPS} = "https://openqa.suse.de/assets/repo/$sle_path";
    $settings->{MIRROR_FTP}   = "ftp://openqa.suse.de/$sle_path";
    $settings->{MIRROR_NFS}   = "nfs://openqa.suse.de/var/lib/openqa/share/factory/repo/$sle_path";
    $settings->{MIRROR_SMB}   = "smb://openqa.suse.de/inst/$sle_path";
}

sub reposync_sle {
    state $ret;
    return $ret if defined $ret;

    my ($cfg, $settings) = @_;

    my $info = $settings->{'.addonsyncinfo'};
    for my $repo (keys %$info) {
        my $targetname = ensure_scc_valid_entry($repo);
        # rename repo if staging
        if(my $staging = $settings->{STAGING}) {
          $targetname = rsync::rename_for_staging_sync($targetname, $staging);
        }
        my $r = rsync::_reposync(location => $info->{$repo}->{url}.'/',
            targetname => $targetname,
            expect_buildid => $info->{$repo}->{expect_buildid},
            buildid_pattern => $info->{$repo}->{buildid_pattern},
        );
        if ($info->{$repo}->{has_license}) {
            $r = rsync::_reposync(location => $info->{$repo}->{url}.'.license/',
                targetname => "$targetname.license",
                expect_buildid => $info->{$repo}->{expect_buildid},
                buildid_pattern => $info->{$repo}->{buildid_pattern},
            );
        }
    }
    # Unset variable, so doesn't trigger build using it
    delete $settings->{'.addonsyncinfo'};
    return $ret;
}

# Separately create ha geo symlinks both for x86_64 and s390x
# pointing to synced ha geo s390x-x86_64 directories, see bsc#976795
sub add_ha_geo_symlink {
    my ($dest) = @_;
    return if ($dest !~ /HA-GEO-POOL-s390x-x86_64/);
    (my $ha_geo_x86_64 = $dest) =~ s/-s390x//;
    (my $ha_geo_s390x  = $dest) =~ s/-x86_64//;
    for my $link ($ha_geo_x86_64, $ha_geo_s390x) {
        next if -e $link;
        symlink(basename($dest), $link) or die "couldn't create symlink $link to $dest: $!";
    }
}

my %current_repos;

# Update a CURRENT directory & hardlink it away when build number changes
# First step POOL is synced from $path/$repo into localhost/$trepo-CURRENT
# Second step POOL in hard-linked from localhost/$trepo-CURRENT into localhost/$build
# If $build in undef then it's parsed from media.1/build
sub update_current_repo {
   my ($path, $repo, $build, $trepo, $staging) = @_;

   # no need to sync twice during one rsync.pl run
   return $current_repos{$repo} if $current_repos{$repo};

   $trepo = ensure_scc_valid_entry($trepo);
   my $dpath = $rsync::options{repodir} . "/$trepo-CURRENT";
   my $rsync = File::Rsync->new(timeout => 3600,
                                 delete => 1,
                                 recursive => 1,
                                 links => 1,
                                 perms => 1,
                                 times => 1,
                                 specials => 1,
                                 ipv4 => 1,
                                 verbose => 1);
   print "syncing $path/$repo/ -> $dpath\n" if $rsync::options{verbose};

   if (!rsync::dryrun()) {
      my $ret = $rsync->exec(src => "$path/$repo/", dest => "$dpath/");
      print $rsync->err if $rsync->err;
      print $rsync->out if $rsync::options{verbose};
      unless (defined $ret && $ret) {
        warn "rsync failed $ret\n";
        return;
      }
    }

    if (!$build && open(BUILD, "$dpath/media.1/build")) {
      $build = <BUILD>;
      chomp $build;
      $build = ensure_scc_valid_entry($build);
      close(BUILD);
    }
    if (!$build && open(BUILD, "$dpath/media.1/media")) {
      my $dummy = <BUILD>;
      $build = <BUILD>;
      chomp $build;
      $build = ensure_scc_valid_entry($build);
      close(BUILD);
    }
    if ($build) {
      if ($staging) {
        $build =~ s,SLE-$rsync::version_in_staging-,SLE-$rsync::version_in_staging-Staging:$staging-,;
      }
      $current_repos{$repo} = $build;
      my $target = $rsync::options{repodir} . "/$build";
      if ($repo =~ m/(-Media[^-]*)$/) {
        $target .= $1;
      }
      print "LINK AWAY $dpath -> $target\n" if $rsync::options{verbose};
      # using rsync here to keep hard links and make it more forgiven to
      # cancelled sync calls
      if (!rsync::dryrun()) {
        my $ret = $rsync->exec(src => "$dpath/", dest => "$target/", 'link-dest' => [ $dpath ]);
        print $rsync->out if $rsync::options{verbose};
        # return undef in case error occured during syncronization
        if($rsync->err) {
            print $rsync->err;
            return undef;
        };

        add_ha_geo_symlink($target);
      }
    }
    return $build;
}

sub add_sle_addons {
    my ($settings) = @_;
    my $arch = $settings->{ARCH};
    my $path;
    # Is used to add letter to the build, as not there in iso directory
    my $staging = $settings->{STAGING};
    # used for sle12 RT only
    my $sp_no = substr($settings->{VERSION}, 5, 1);
    if($staging) {
      $path = "dist.suse.de::repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/Staging:/$staging/images/iso";
    } else {
      $path = "dist.suse.de::repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/TEST/images/iso/";
    }
    # Do not downoad iso for s390x as we cannot use iso
    if ($rsync::major_version >= 15 && $arch ne 's390x') {
        # https://progress.opensuse.org/issues/25454 All modules/packages medium
        $settings->{_ISO_1} = latest_iso($path, "SLE-$rsync::version_in_staging-Packages-$arch-Build*-Media1.iso");
    }
    else {
        # for s390x we cannot use iso and repo is synced later, so no need to extract iso
        if($arch ne 's390x') {
            $settings->{_ISO_1} = latest_iso($path, "SLE-$rsync::version_in_staging-SDK-DVD-$arch-Build*-Media1.iso");
            $settings->{BUILD_SDK} = extract_build($settings->{_ISO_1});
        }
        $settings->{_ISO_2} = latest_iso($path, "SLE-$rsync::version_in_staging-HA-DVD-$arch-Build*-Media1.iso");
        $settings->{BUILD_HA} = extract_build($settings->{_ISO_2});
        if ($arch eq 'x86_64' || $arch eq 's390x') {
            $settings->{_ISO_3} = latest_iso($path, "SLE-$rsync::version_in_staging-HA-GEO-DVD-s390x-x86_64-Build*-Media.iso");
            $settings->{BUILD_HA_GEO} = extract_build($settings->{_ISO_3});
        }
        if ($arch eq 'x86_64') {
            # SLE15+ does not have RT extension anymore
            $settings->{_ISO_5} = latest_iso("dist.suse.de::repos/Devel:/RTE:/SLE12SP$sp_no/images/iso", "SLE-12-SP$sp_no-RT-DVD-x86_64-Build*-Media1.iso");
            $settings->{BUILD_RT} = extract_build($settings->{_ISO_5});
            $settings->{_ISO_6} = latest_iso($path, "SLE-$rsync::version_in_staging-WE-DVD-x86_64-Build*-Media1.iso");
            $settings->{BUILD_WE} = extract_build($settings->{_ISO_6});
        }
    }
    # Rename all build variables if Staging
    if($staging) {
      for my $build_var (qw(BUILD_HA BUILD_RT BUILD_WE)) {
        $settings->{$build_var} = "$staging." . $settings->{$build_var} if $settings->{$build_var};
      }
    }
    # if you add more, don't forget to update var 'i' down there
    if (rsync::use_fake_scc($settings)) {
        # list of repos to sync.
        # name: part of directory name on dist
        # scc:  identifier of the extension in the scc json file
        # repo: name of the pool repo
        # has_license: set to also rsync extra license directory
        # nonfree: set to also add regkey for that
        # mustmatch: which DVD flavor to sync this for. buildid of that repo must match repo of the DVD
        # medium: '1' is for binary RPMs (the default), '2' for source RPMs, and '3' for RPMs with debug information
        # set_build_nr: if true script will set BUILD_%name% variable with addon build version, unless it's already set
        my @products = (
            { name => 'Module-Basesystem', scc => 'sle-15-base-tools', repo => "SLE-Module-Basesystem", has_license => 0, nonfree => 1 },
            { name => 'Module-Basesystem', scc => 'sle-15-base-tools', repo => "SLE-Module-Basesystem-Source", has_license => 0, nonfree => 1, medium => 2 },
            { name => 'Module-Basesystem', scc => 'sle-15-base-tools', repo => "SLE-Module-Basesystem-Debug", has_license => 0, nonfree => 1, medium => 3 },
            { name => 'Module-Desktop-Applications', scc => 'sle-15-desktop-apps', repo => "SLE-Module-Desktop-Applications", has_license => 0, nonfree => 1 },
            { name => 'Module-Development-Tools', scc => 'sle-15-dev-tools', repo => "SLE-Module-Development-Tools", has_license => 0, nonfree => 1 },
            { name => 'Module-Legacy', scc => 'sle-15-legacy', repo => "SLE-Module-Legacy", has_license => 0, nonfree => 1 },
            { name => 'Module-SAP-Applications', scc => 'sle-15-sap-apps', repo => "SLE-Module-SAP-Applications", has_license => 0, nonfree => 1 },
            { name => 'Module-Server-Applications', scc => 'sle-15-server-apps', repo => "SLE-Module-Server-Applications", has_license => 0, nonfree => 1 },
            { name => 'Module-Public-Cloud', scc => 'sle-15-public-cloud', repo => "SLE-Module-Public-Cloud", has_license => 0, nonfree => 1 },
            { name => 'Module-CAP-Tools', scc => 'sle-15-cap-tools', repo => "SLE-Module-CAP-Tools", has_license => 0, nonfree => 1, archs => [ qw/x86_64/ ] },
            { name => 'Module-Web-Scripting', scc => 'sle-15-web-scripting', repo => "SLE-Module-Web-Scripting", has_license => 0, nonfree => 1 },
            { name => 'Module-Containers', scc => 'sle-15-containers', repo => "SLE-Module-Containers", has_license => 0, nonfree => 1, archs => [ qw/ppc64le s390x x86_64 aarch64/ ] },
            { name => 'Module-Live-Patching', scc => 'sle-15-live-patching', repo => "SLE-Module-Live-Patching", has_license => 0, nonfree => 1, archs => [ qw/ppc64le x86_64/ ] },
            { name => 'Module-Transactional-Server', scc => 'sle-15-transactional-server', repo => "SLE-Module-Transactional-Server", has_license => 0, nonfree => 1 },
            { name => 'Module-Python2', scc => 'sle-15-python2', repo => "SLE-Module-Python2", has_license => 0, nonfree => 1 },
            { name => 'Module-Packagehub-Subpackages', scc => 'sle-15-module-packagehub-subpackages', repo => "SLE-Module-Packagehub-Subpackages", has_license => 0, nonfree => 1 },
            { name => 'Module-HPC', scc => 'hpc-module', repo => "SLE-Module-HPC", has_license => 0, nonfree => 1, archs => [ qw/x86_64 aarch64/ ] },
            { name => 'Module-RT', scc => 'rt-module', repo => "SLE-Module-RT", has_license => 0, nonfree => 1, archs => [ qw/x86_64/ ] },
            { name => 'Product-SLES', scc => 'sles-product', repo => "SLE-Product-SLES", has_license => $staging ? 0 : 1, nonfree => 1 },
            { name => 'Product-SLED', scc => 'sled-product', repo => "SLE-Product-SLED", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64/ ] },
            { name => 'Product-SLES_SAP', scc => 'sles_sap-product', repo => "SLE-Product-SLES_SAP", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64 ppc64le/ ] },
            { name => 'Product-HPC', scc => 'hpc-product', repo => "SLE-Product-HPC", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64 aarch64/ ] },
            { name => 'Product-RT', scc => 'rt-product', repo => "SLE-Product-RT", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64/ ] },
            { name => 'Product-WE', scc => 'we-product', repo => "SLE-Product-WE", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64/ ] },
            { name => 'Product-HA', scc => 'ha-product', repo => "SLE-Product-HA", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/ppc64le s390x x86_64 aarch64/ ] },
            { name => 'Product-SLES-BCL', scc => 'sles-bcl-product', repo => "SLE-Product-SLES-BCL", has_license => 0, nonfree => 1, archs => [ qw/x86_64/ ] },
        );
        # Here is part which either not expected for sle 15 (or not with the same name/definition) or doesn't work at the moment.
        # SDK is not availble for SLE15. See bsc#1054224
        if($rsync::major_version < 15) {
            push @products, { name => 'Server', scc => 'SLES', repo => "SLES-Pool", mustmatch => 'Server-DVD' };
            push @products, { name => 'Server', scc => 'SLES', repo => "SLES-Pool-Source", mustmatch => 'Server-DVD', medium => 2 };
            push @products, { name => 'Server', scc => 'SLES', repo => "SLES-Pool-Debug", mustmatch => 'Server-DVD', medium => 3 };
            push @products, { name => 'Desktop', scc => 'SLED', repo => "SLED-Pool", mustmatch => 'Desktop-DVD' };
            push @products, { name => 'SDK', scc => 'sle-sdk', repo => "SLE-SDK-Pool", has_license => $staging ? 0 : 1, set_build_nr => $staging ? 0 : 1 };
            push @products, { name => 'WE', scc => 'sle-we', repo => "SLE-WE-Pool", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64/ ] };
            push @products, { name => 'HA', scc => 'sle-ha', repo => "SLE-HA-Pool", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/ppc64le s390x x86_64/ ] };
            push @products, { name => 'HA-GEO', scc => 'sle-ha-geo', repo => "SLE-HA-GEO-Pool", has_license => $staging ? 0 : 1, nonfree => 1, archs => { x86_64 => 's390x-x86_64', s390x => 's390x-x86_64'} };
            push @products, { name => 'RT', scc => 'sle-rt', repo => "SLE-RT-Pool", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64/ ] };
            push @products, { name => 'SAP', scc => 'SLES_SAP', repo => "SLES_SAP-Pool", mustmatch => 'SAP-DVD', archs => [ qw/x86_64 ppc64le/ ] };
            push @products, { name => 'HPC', scc => 'HPC', repo => "SLE-HPC-Pool", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64 aarch64/ ] };
            push @products, { name => 'Live-Patching', scc => 'sle-live-patching', repo => "SLE-Live-Patching-Pool", has_license => $staging ? 0 : 1, nonfree => 1, archs => [ qw/x86_64 ppc64le/ ] };
        }
        my $info;
        my $i = 9; # start one higher than last iso, to retain potential ISO_x -> REPO_x mapping
        for my $p (@products) {
            my $name   = $p->{name};
            # Set path differently for staging and other modules
            $path = $staging ? "rsync://dist.suse.de/repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/Staging:/$staging/images/repo"
                             : "rsync://dist.suse.de/repos/SUSE:/SLE-$rsync::version_in_staging:/GA:/TEST/images/repo";
            if ($p->{name} eq 'RT') {
                $path = "rsync://dist.suse.de/repos/Devel:/RTE:/SLE12SP4/images/repo";
            }

            print "add_sle_addons: product: '$name'\n" if $rsync::options{verbose};
            if ($p->{mustmatch}) {
                next unless $p->{mustmatch} eq $settings->{FLAVOR};
            }
            my $medium = 1;
            if ($p->{medium}) {
                $medium = $p->{medium};
            }
            my $poolarch = $arch;
            if ($p->{archs}) {
                if (ref($p->{archs}) eq 'ARRAY') {
                        next unless grep { $arch eq $_ } @{$p->{archs}};
                } else {
                        $poolarch = $p->{archs}->{$arch};
                        next unless $poolarch;
                }
            }
            print "add_sle_addons: update_current_repo: '$name'\n" if $rsync::options{verbose};
            # RT repo path is valid only for sle12
            my $repo = ($name =~ /RT/ and defined($settings->{BUILD_RT})) ? "SLE-12-SP4-$name-POOL-$poolarch-Build$settings->{BUILD_RT}-Media$medium" :
                    "SLE-$rsync::version_in_staging-$name-POOL-$poolarch-Media$medium";
            my $trepo = $repo;
            if ($staging) {
                $trepo = "SLE-$rsync::version_in_staging-Staging:$staging-$name-POOL-$poolarch-Media$medium";
            }
            my $build = update_current_repo($path, $repo, undef, $trepo, $staging);
            if ($build && $p->{has_license}) {
                # SES name has unique syntax (SUSE-Enterprise-Storage-6-POOL-x86_64-Media1), different from all other modules
                $repo = $name =~ /Storage/ ? "$name-POOL-$poolarch-Media$medium.license"
                      : $name =~ /RT/ ? "SLE-12-SP4-$name-POOL-$poolarch-Build$settings->{BUILD_RT}-Media$medium.license"
                      : "SLE-$rsync::version_in_staging-$name-POOL-$poolarch-Media$medium.license";
                unless(update_current_repo($path, $repo, $build, $repo, $staging))
                {
                    print STDERR "Failed to sync license repo for $name, continuing without it\n";
                    $p->{has_license} = undef;
                }
            }
            my $url;
            if ($build) {
                $url = "$build-Media$medium";
            } else {
                $url = latest_iso($path, "SLE-$rsync::version_in_staging-$name-POOL-$poolarch-*Media$medium");
            }
            unless ($url) {
                print "add_sle_addons: No url found for: '$name'\n" if $rsync::options{verbose};
                next;
            }
            my $base = basename($url);
            #store some information for reposync_sle
            $info->{$base} = {
                url => $url,
                %{$p},
            };
            if ($p->{mustmatch}) {
                $info->{$base}->{expect_buildid} = $settings->{BUILD};
                $info->{$base}->{buildid_pattern} = qr/^SLE-$rsync::version_in_staging-(?<flavor>(?:Server|Desktop|SAP)-POOL)-(?<arch>[^-]+)-Build(?<build>[^-]+)/;
            }
            my $exported_repo_name  = $p->{repo};
            $exported_repo_name     =~ s/-Pool//;
            $exported_repo_name     =~ s/-/_/g;
            # Set build numbers for addons, where we don't sync iso (e.g. s390x)
            if($p->{set_build_nr}) {
                my $build_var = 'BUILD_' . $p->{name};
                if(!defined($settings->{$build_var}) && (my $build_nr=extract_build($build)))
                {
                    $settings->{$build_var} = $build_nr;
                }
            }
            my $scc_valid_base      = ensure_scc_valid_entry($base);
            $settings->{uc "REPO_$exported_repo_name"} = $scc_valid_base;
            $settings->{"REPO_$i"} = $scc_valid_base;
            ++$i;
            if ($p->{has_license}) {
                $settings->{"REPO_$i"} = $scc_valid_base.'.license';
                ++$i;
            }
        }
        $settings->{'.addonsyncinfo'} = $info;
    }
}

sub compute_register_sle {
    my $settings = shift;
    my @ret = ($settings);
    # split out HA & RT as it should have a different build number in a
    # new job group
    if ($settings->{FLAVOR} eq 'Server-DVD' && $settings->{BUILD_HA}) {
        # clone HA
        my %newha = %$settings;
        $newha{BUILD} = $settings->{BUILD_HA} . "@" . $settings->{BUILD_SLE};
        $newha{FLAVOR} = "Server-DVD-HA";
        push(@ret, \%newha);
    }
    if ($settings->{FLAVOR} eq 'Server-DVD' && $settings->{BUILD_RT}) {
        # clone RT
        my %newrt = %$settings;
        $newrt{BUILD} = $settings->{BUILD_RT} . "@" . $settings->{BUILD_SLE};
        $newrt{FLAVOR} = "Server-DVD-RT";
        push(@ret, \%newrt);
    }
    if ($settings->{FLAVOR} eq 'Installer-DVD' && $settings->{VERSION} eq '15-SP2') {
        # create migration flavors for 15sp2
        my @flavors = ("Migration-from-SLE11-SP4-to-SLE15-SP2", "Migration-from-SLE12-SP5-to-SLE15-SP2", "Migration-from-SLE15-SPX-to-SLE15-SP2", "Regression-on-Migration-from-SLE11-SP4-to-SLE15-SP2", "Regression-on-Migration-from-SLE12-SP5-to-SLE15-SP2", "Regression-on-Migration-from-SLE15-SPX-to-SLE15-SP2");
        foreach my $flavor (@flavors) {
            my %new_migration = %$settings;
            $new_migration{FLAVOR} = $flavor;
            push(@ret, \%new_migration);
        }
    }
    return @ret;
}

sub register_staging_s390 {
   my ($settings) = @_;
   $settings->{REPO_0} = extract_iso_as_repo(dirfor($settings->{ISO}));
}

sub latest_iso {
    my ($path, $glob) = @_;
    my $rsync = File::Rsync->new(src => "$path/$glob", timeout => 3600);
    my $last;
    for my $name ($rsync->list) {
      chomp $name;
      $name =~ s/\\n$//;
      $name =~ s/.* //;
      $last = "$path/$name";
    }
    #warn "Can't find any of $path/$glob\n" unless $last;
    return $last;
}

sub latest_live_patch {
    my $glob = $_[0];
    my $ftp_site     = 'openqa.suse.de';
    my $ftp_user     = 'anonymous';
    my $ftp_password = '';
    my $last;

    my $ftp = Net::FTP->new($ftp_site)
     or die "Could not connect to $ftp_site: $!";

    $ftp->login($ftp_user, $ftp_password)
     or die "Could not login to $ftp_site with user $ftp_user: $!";

    my @remote_files = $ftp->ls($glob);
    foreach my $file (@remote_files) {
     $last = $file;
    }
    $ftp->quit();
    return $last;

}

sub current_sle11_addons {
    my ($path, $arch) = @_;
    my %settings;

    $settings{ISO_1} = latest_iso($path, "SLE-11-SP4-SDK-DVD-$arch-Build*-Media1.iso");
    $settings{ISO_2} = latest_iso($path, "SLE-HA-11-SP4-$arch-Build*-Media1.iso");

    # SMT addon. Will not be registered but used on SLE11-SP4. Hardcoded to
    # build 0008 on request of Marita.
    $settings{ISO_3} = "SLE-11-SMT-SP3-i586-s390x-x86_64-Build0008-Media1.iso";

    if ($arch eq 'x86_64' || $arch eq 's390x') {
      $settings{ISO_4} = latest_iso($path, "SLE-HA-GEO-11-SP4-s390x-x86_64-Build*-Media.iso");
    }

    return %settings;
}

sub extract_build {
    my ($iso) = @_;
    return unless $iso;

    if ($iso =~ /-Build(.*)-/) {
        return $1;
    }
    # When extract build number from the repo name, we have it in the end of the string
    if ($iso =~ /-Build(\d+(\.\d+)?)$/) {
        return $1;
    }
    return;
}

sub override_methods {
    $rsync::override->replace('rsync::rename_for_staging_sync_override' => sub {
            my ($name, $staging, $version_in_staging) = @_;
            # Replace prefix
            $name =~ s/^SLE-$version_in_staging-/SLE-$version_in_staging-Staging:$staging-/;
            return $name;
        });

    $rsync::override->replace('rsync::repo_name_override' => sub {
            return rsync_sle::ensure_scc_valid_entry(shift);
        });

    $rsync::override->replace('rsync::skip_repo_override' => sub {
            my (%args) = @_;
            my $version = $args{version_in_staging};
            return 0 unless ($args{name} =~ /SLE-$version-Server-MINI-ISO-x86_64-Build(\d+)-Media.iso/);
            my $dvd = "SLE-$version-Server-DVD-x86_64-Build$1-Media1";
            unless ( -d $args{repodir} .'/'. $dvd || grep( /$dvd/, @{$args{rlist}} ) ) {
                warn "Skipping SLES-MINI, DVD mirror is not ready!\n";
                return 1;
            }
            return 0;
        });
}

1;
# vim: sw=4 et

# vim: ts=4 sts=4 sw=4 et: syntax=perl
#
# Copyright (c) 2017-2023 Sven Kirmess
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use 5.010;
use strict;
use warnings;

package Dist::Zilla::PluginBundle::Author::SKIRMESS;

our $VERSION = '1.000';

use Moose 0.99;

with 'Dist::Zilla::Role::PluginBundle::Easy';

use Carp                                 qw(confess);
use CPAN::Meta::Prereqs                  ();
use CPAN::Meta::Requirements             ();
use Dist::Zilla::File::OnDisk            ();
use Dist::Zilla::Types 6.000             qw(Path);
use Dist::Zilla::Util                    ();
use Dist::Zilla::Util::BundleInfo        ();
use Dist::Zilla::Util::ExpandINI::Reader ();
use File::Temp                           ();
use JSON::PP                             ();
use List::Util                           qw(pairs);
use Local::Software::License::ISC        ();
use Module::CoreList 2.77                ();
use Module::CPANfile 1.1004              ();
use Module::Metadata                     ();
use Path::Tiny                           qw(path);
use Perl::Critic::MergeProfile           ();
use Scalar::Util                         qw(blessed);
use Term::ANSIColor                      qw(colored);
use YAML::Tiny                           qw();
use version 0.77;

use Config::MVP 2.200012 ();    # https://github.com/rjbs/Config-MVP/issues/13

use namespace::autoclean 0.09;

# The checkout location of this bundle
has _bundle_checkout_path => (
    is       => 'ro',
    isa      => Path,
    default  => sub { path(__FILE__)->absolute->parent(6) },
    init_arg => undef,
);

# The Author::SKIRMESS plugin bundle is used to build other distributions
# with Dist::Zilla, but it is also used to build the bundle itself.
# When the bundle is built some plugins require a different configuration
# or are skipped.
#
# If __FILE__ is inside lib of the cwd we are building the bundle. Otherwise
# we use the bundle to build another distribution.
#
# Note: This is not "lazy" because if we ever change the directory it would
# produce wrong results.
has _self_build => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub {
        Path::Tiny->cwd->absolute->stringify eq $_[0]->_bundle_checkout_path->stringify;
    },
    init_arg => undef,
);

# Use the SetScriptShebang plugin to adjust the shebang line in scripts
has set_script_shebang => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('set_script_shebang') // 1;
    },
    init_arg => undef,
);

sub configure {
    my ($self) = @_;

    # Without this, Local::Test::TempDir creates the tmp directory
    # inside the release during a 'dzil release' which breaks the
    # release
    $ENV{LOCAL_TEST_TEMPDIR_BASEDIR} = path(q{.})->absolute->stringify;    ## no critic (Variables::RequireLocalizedPunctuationVars)

    my $self_build = $self->_self_build;

    my @generated_files = qw(
      CONTRIBUTING
      cpanfile
      LICENSE
      Makefile.PL
      META.json
      META.yml
      README
      README.md
      t/00-load.t
    );

    # Add contributor names from git to your distribution
    $self->add_plugins('Git::Contributors');

    # Gather all tracked files in a Git working directory
    $self->add_plugins(
        [
            'Git::GatherDir',
            {
                ':version'       => '2.016',
                exclude_filename => [
                    'dist.ini',
                    @generated_files,
                ],
                exclude_match    => '^xt/(?!lib/).+/',
                include_dotfiles => 1,
            },
        ],
    );

    # Set the distribution version from your main module's $VERSION
    $self->add_plugins('VersionFromMainModule');

    # Bump and reversion $VERSION on release
    $self->add_plugins(
        [
            'ReversionOnRelease',
            {
                prompt => 1,
            },
        ],
    );

    # Create the t/00-load.t test
    $self->add_plugins('Author::SKIRMESS::Test::Load');

    # update Pod with project specific defaults
    $self->add_plugins('Author::SKIRMESS::UpdatePod');

    # fix the file permissions in your Git repository with Dist::Zilla
    $self->add_plugins(
        [
            'Git::FilePermissions',
            {
                perms => ['^bin/ 0755'],
            },
        ],
    );

    # Enforce the correct line endings in your Git repository with Dist::Zilla
    $self->add_plugins('Git::RequireUnixEOL');

    # Update the next release number in your changelog
    $self->add_plugins(
        [
            'NextRelease',
            {
                format    => '%v  %{yyyy-MM-dd HH:mm:ss VVV}d',
                time_zone => 'UTC',
            },
        ],
    );

    # Prune stuff that you probably don't mean to include
    $self->add_plugins('PruneCruft');

    # Decline to build files that appear in a MANIFEST.SKIP-like file
    $self->add_plugins('ManifestSkip');

    # automatically extract prereqs from your modules
    #   :InstallModules -> ^lib/.*\.(?:pm|pod)$
    #   :ExecFiles      -> everything under bin through ExecDir
    #   :TestFiles      -> ^t/
    #   :ExtraTestFiles -> ^xt/ (only extended tests in our case)
    $self->add_plugins('AutoPrereqs');

    # Detects the minimum version of Perl required for your dist
    $self->add_plugins('Author::SKIRMESS::MinimumPerl');

    # Smoker prereqs (xt/*.t) are added as develop dependencies by
    # AutoPrereqs above - save them to a variable because we need them for
    # the Makefile.PL.
    my $extended_requires;
    $self->add_plugins(
        [
            'Code::PrereqSource',
            'SaveSmokerPrereqs',
            {
                register_prereqs => sub {
                    my ($self) = @_;

                    my $cpan_meta_prereqs = $self->zilla->prereqs->cpan_meta_prereqs;

                    my @types = $cpan_meta_prereqs->types_in('develop');
                    $self->log_fatal(q{We can only handle 'requires' in 'develop' prereqs}) if @types > 1 || $types[0] ne 'requires';

                    my $cpan_meta_requirements = $self->zilla->prereqs->cpan_meta_prereqs->requirements_for( 'develop', 'requires' );
                    $extended_requires = $cpan_meta_requirements->as_string_hash;

                    return;
                },
            },
        ],
    );

    # :ExtraTestFiles contains only the extended tests, or is empty, because
    # we don't add xt test files to the distribution, that's why we have to
    # create a new ExtraTestFiles plugin
    $self->add_plugins(
        [
            'FinderCode', 'ExtraTestFiles',
            {
                code  => \&_find_files_extra_tests_files,
                style => 'list',
            },
        ],
    );

    # Scan again for prereqs but include the author and release tests from
    # the Git project.
    #
    # We have to scan everything again because the modules provided by this
    # distribution aren't saved and if we would only scan the author and
    # release tests we would add dependencies on this distributions modules.
    #
    #   :InstallModules -> ^lib/.*\.(?:pm|pod)$
    #   :ExecFiles      -> everything under bin through ExecDir
    #   :TestFiles      -> ^t/
    #   :ExtraTestFiles -> ^xt/ (only extended tests in our case)
    #   @Author::SKIRMESS/ExtraTestFiles
    #                   -> everything under xt in the project (not the dist)
    $self->add_plugins(
        [
            'AutoPrereqs',
            'AutoPrereqs/WithAuthorAndReleaseTests',
            {
                develop_finder => [qw( :ExtraTestFiles @Author::SKIRMESS/ExtraTestFiles)],
            },
        ],
    );

    # automatically extract Perl::Critic policy prereqs
    for my $test_type (qw(code tests)) {
        my $rc_file = 'xt/author/perlcriticrc';
        if ( -f "xt/author/perlcriticrc-$test_type" ) {
            my $merge = Perl::Critic::MergeProfile->new;
            $merge->read('xt/author/perlcriticrc');
            $merge->read("xt/author/perlcriticrc-$test_type");

            $rc_file = $self->_tempfile();
            $merge->write($rc_file) or $self->log_fatal("Cannot write merged Perl::Critic profile to $rc_file: $!");
        }

        $self->add_plugins(
            [
                'AutoPrereqs::Perl::Critic', "AutoPrereqs::Perl::Critic / $test_type",
                {
                    critic_config => $rc_file,
                },
            ],
        );
    }

    # Remove the develop prereqs and save them to a variable
    my $develop_requires_prereqs;
    $self->add_plugins(
        [
            'Code::PrereqSource',
            'SaveAndRemoveDevelopPrereqs',
            {
                register_prereqs => sub {
                    my ($self) = @_;

                    my $cpan_meta_prereqs = $self->zilla->prereqs->cpan_meta_prereqs;

                    my @types = $cpan_meta_prereqs->types_in('develop');
                    $self->log_fatal(q{We can only handle 'requires' in 'develop' prereqs}) if @types > 1 || $types[0] ne 'requires';

                    my $cpan_meta_requirements = $self->zilla->prereqs->cpan_meta_prereqs->requirements_for( 'develop', 'requires' );
                    $develop_requires_prereqs = $cpan_meta_requirements->clone;

                    for my $module ( keys %{ $cpan_meta_requirements->as_string_hash } ) {
                        $cpan_meta_requirements->clear_requirement($module);
                    }

                    return;
                },
            },
        ],
    );

    # Set script shebang to #!perl
    if ( $self->set_script_shebang ) {
        $self->add_plugins('SetScriptShebang');
    }

    # Stop CPAN from indexing stuff
    $self->add_plugins(
        [
            'MetaNoIndex',
            {
                directory => [ qw(t xt), grep { -d } qw(corpus demo examples fatlib inc local perl5 share) ],
            },
        ],
    );

    # Automatically include GitHub meta information in META.yml
    # (collects the info for Author::SKIRMESS::UpdatePod)
    $self->add_plugins(
        [
            'GithubMeta',
            {
                issues => 1,
            },
        ],
    );

    # Check for non-core dependencies
    my $latest_perl_known_to_module_corelist = ( sort map { version->new($_) } keys %Module::CoreList::released )[-1]->numify;
    my $latest_perl_version_which_contains_all_required_core_modules;
    $self->add_plugins(
        [
            'Code::AfterBuild',
            'DependenciesAreInCore',
            {
                after_build => sub {
                    my ( $self, $payload ) = @_;

                    my $prereqs = $self->zilla->prereqs->cpan_meta_prereqs;

                    my $req_hash = $prereqs->requirements_for( 'runtime', 'requires' )->clone->add_requirements( $prereqs->requirements_for( 'configure', 'requires' ) )->as_string_hash;

                    my @modules_core;
                    my @modules_not_core;
                    my @perl_core_versions_used = ( version->parse('v5.6.0') );
                  MODULE:
                    for my $module ( sort keys %{$req_hash} ) {
                        next MODULE if $module eq 'perl';

                        my $version = $req_hash->{$module};

                        if ( Module::CoreList->is_core( $module, undef, $latest_perl_known_to_module_corelist ) ) {
                            push @modules_core, [ lc($module), version->new( Module::CoreList->first_release( $module, $version ) ), $module, $version ];
                        }
                        else {
                            push @modules_not_core, [ lc($module), $module, $version ];
                        }
                    }

                    for my $module_ref ( sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] } @modules_core ) {
                        my $name = $module_ref->[2];
                        if ( $module_ref->[3] ne '0' ) {
                            $name .= " $module_ref->[3]";
                        }

                        $self->log( "Dependency $name (core since " . $module_ref->[1]->normal . ')' );

                        push @perl_core_versions_used, version->parse( $module_ref->[1]->normal );
                    }

                    for my $module_ref ( sort { $a->[0] cmp $b->[0] } @modules_not_core ) {
                        my $name = $module_ref->[1];
                        if ( $module_ref->[2] ne '0' ) {
                            $name .= " $module_ref->[2]";
                        }

                        $self->log( colored( "Dependency $name (not in core)", 'magenta' ) );
                    }

                    $latest_perl_version_which_contains_all_required_core_modules = ( reverse sort @perl_core_versions_used )[0];
                },
            },
        ],
    );

    # Check if tests add a non-core dependency
    $self->add_plugins(
        [
            'Code::AfterBuild',
            'TestDependenciesAreInCore',
            {
                after_build => sub {
                    my ( $self, $payload ) = @_;

                    my $prereqs = $self->zilla->prereqs->cpan_meta_prereqs;

                    my $req = $prereqs->requirements_for( 'runtime', 'requires' )->clone->add_requirements( $prereqs->requirements_for( 'configure', 'requires' ) );

                    my $req_test = $prereqs->requirements_for( 'test', 'requires' );

                    my $req_hash     = $req->as_string_hash;
                    my $req_all_hash = $req_test->clone->add_requirements($req)->as_string_hash;

                    for my $module ( keys %{$req_hash} ) {
                        $self->log_fatal("internal error: module = $module") if !exists $req_all_hash->{$module};

                        if ( $req_hash->{$module} eq $req_all_hash->{$module} ) {
                            delete $req_all_hash->{$module};
                        }
                    }

                    my @modules_core;
                    my @modules_not_core;
                  MODULE:
                    for my $module ( sort keys %{$req_all_hash} ) {
                        next MODULE if $module eq 'perl';

                        my $version = $req_all_hash->{$module};

                        if ( Module::CoreList->is_core( $module, undef, $latest_perl_known_to_module_corelist ) ) {
                            push @modules_core, [ lc($module), version->new( Module::CoreList->first_release( $module, $version ) ), $module, $version ];
                        }
                        else {
                            push @modules_not_core, [ lc($module), $module, $version ];
                        }
                    }

                    for my $module_ref ( sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] } @modules_core ) {
                        my $name = $module_ref->[2];
                        if ( $module_ref->[3] ne '0' ) {
                            $name .= " $module_ref->[3]";
                        }

                        if ( version->parse( $module_ref->[1]->normal ) > $latest_perl_version_which_contains_all_required_core_modules ) {
                            $self->log( colored( "Dependency $name added by tests (core since " . $module_ref->[1]->normal . ')', 'yellow' ) );
                        }
                        else {
                            $self->log( "Dependency $name added by tests (core since " . $module_ref->[1]->normal . ')' );
                        }
                    }

                    for my $module_ref ( sort { $a->[0] cmp $b->[0] } @modules_not_core ) {
                        my $name = $module_ref->[1];
                        if ( $module_ref->[2] ne '0' ) {
                            $name .= " $module_ref->[2]";
                        }

                        $self->log( colored( "Dependency $name added by tests !!! NOT A CORE DEPENDENCY !!!", 'red' ) );
                    }
                },
            },
        ],
    );

    # Automatically convert POD to a README in any format for Dist::Zilla
    $self->add_plugins(
        [
            'ReadmeAnyFromPod',
            {
                type     => 'markdown',
                filename => 'README.md',
                location => 'root',
            },
        ],
    );

    # Produce a META.yml
    $self->add_plugins('MetaYAML');

    # Remove churn from META.yml
    $self->add_plugins(
        [
            'Code::FileMunger',
            'MetaYAML/RemoveChurn',
            {
                munge_file => sub {
                    my ( $self, $file ) = @_;

                    return if $file->name ne 'META.yml';

                    $self->log_fatal( q{'} . $file->name . q{' is not a 'Dist::Zilla::File::FromCode'} ) if blessed($file) ne 'Dist::Zilla::File::FromCode';

                    my $orig_coderef = $file->code();
                    $file->code(
                        sub {
                            $self->log_debug( [ 'Removing churn from %s', $file->name ] );

                            my $meta_yaml = YAML::Tiny->read_string( $file->$orig_coderef() );
                            $meta_yaml->[0]->{generated_by} =~ s{ \s+ version \s+ .+? ( , | $ ) }{$1}xsmg;
                            delete $meta_yaml->[0]->{x_generated_by_perl};
                            delete $meta_yaml->[0]->{x_serialization_backend};

                            # Set dynamic_config to true in META.* files if we have extended prereqs
                            if ( keys %{$extended_requires} ) {
                                $meta_yaml->[0]->{dynamic_config} = 1;
                            }
                            else {
                                $self->log_fatal(q{dynamic_config is true but we don't have any extended prereqs}) if $meta_yaml->[0]->{dynamic_config};

                                # convert it to numeric from string
                                $meta_yaml->[0]->{dynamic_config} = 0;
                            }

                            my $content = $meta_yaml->write_string;
                            return $content;
                        },
                    );

                    return;
                },
            },
        ],
    );

    # Produce a META.json
    $self->add_plugins('MetaJSON');

    # Remove churn from META.json
    $self->add_plugins(
        [
            'Code::FileMunger',
            'MetaJSON/RemoveChurn',
            {
                munge_file => sub {
                    my ( $self, $file ) = @_;

                    return if $file->name ne 'META.json';

                    $self->log_fatal( q{'} . $file->name . q{' is not a 'Dist::Zilla::File::FromCode'} ) if blessed($file) ne 'Dist::Zilla::File::FromCode';

                    my $orig_coderef = $file->code();
                    $file->code(
                        sub {
                            $self->log_debug( [ 'Removing churn from %s', $file->name ] );

                            my $json = JSON::PP->new->canonical->pretty->ascii;

                            my $meta_json = $json->decode( $file->$orig_coderef() );
                            $meta_json->{generated_by} =~ s{ \s+ version \s+ .+? ( , | $ ) }{$1}xsmg;
                            delete $meta_json->{x_generated_by_perl};
                            delete $meta_json->{x_serialization_backend};

                            # Set dynamic_config to true in META.* files if we have extended prereqs
                            if ( keys %{$extended_requires} ) {
                                $meta_json->{dynamic_config} = 1;
                            }
                            else {
                                $self->log_fatal(q{dynamic_config is true but we don't have any extended prereqs}) if $meta_json->{dynamic_config};
                            }

                            my $content = $json->encode($meta_json) . "\n";
                            return $content;
                        },
                    );

                    return;
                },
            },
        ],
    );

    # Create a cpanfile in the project root, but not in the distribution.
    my $_bundle_checkout_path = $self->_bundle_checkout_path;
    $self->add_plugins(
        [
            'Code::AfterBuild',
            'CPANfile',
            {
                after_build => sub {
                    my ( $self, $payload ) = @_;

                    # Merge prereqs with removed develop prereqs. These will
                    # be the runtime, test and develop entries of the
                    # cpanfile. The dependencies for xt/*.t, xt/author,
                    # and xt/release are under develop.
                    my $cpanfile_project_prereqs = $self->zilla->prereqs->cpan_meta_prereqs->clone->with_merged_prereqs(
                        CPAN::Meta::Prereqs->new(
                            {
                                develop => { requires => $develop_requires_prereqs->as_string_hash },
                            },
                        ),
                    );

                    # Requirements of the SKIRMESS bundle
                    my $dzil_req;
                    if ($self_build) {

                        # We are the bundle - start with nothing
                        $dzil_req = CPAN::Meta::Requirements->new;
                    }
                    else {
                        # Add runtime prereqs from the bundle
                        my $cpanfile_obj = Module::CPANfile->load( $_bundle_checkout_path->child('cpanfile') );
                        $dzil_req = $cpanfile_obj->prereqs->requirements_for( 'runtime', 'requires' )->clone;
                    }

                    # Add Dist::Zilla as dependency
                    $dzil_req->add_minimum( 'Dist::Zilla', 0 );

                    # Plugins to not depend on because they are in the bundle
                    my %dzil_bundle_package = map { $_ => 1 }
                      grep { !m{ ^ Dist :: Zilla :: PluginBundle :: }xsm }
                      sort
                      keys %{ Module::Metadata->package_versions_from_directory( $_bundle_checkout_path->child('lib')->stringify ) };

                    # Add requirements from dist.ini as develop requirements
                    # (feature dzil)
                    my $dzil_dev_req = CPAN::Meta::Requirements->new;
                    my $dist_ini     = path( $self->zilla->root )->child('dist.ini');
                    $self->log_fatal("File '$dist_ini' does not exist") if !-f $dist_ini;

                    my $reader = Dist::Zilla::Util::ExpandINI::Reader->new();
                  SECTION:
                    for my $section ( @{ $reader->read_file( $dist_ini->stringify ) } ) {
                        my $version = _get_version_from_section( $section->{lines} );

                        if ( $section->{name} eq '_' ) {

                            # Add Dist::Zilla
                            $dzil_dev_req->add_minimum( 'Dist::Zilla', $version );
                            next SECTION;
                        }

                        my $package_name = Dist::Zilla::Util->expand_config_package_name( $section->{package} );
                        next SECTION if exists $dzil_bundle_package{$package_name};

                        if ( $section->{package} !~ m{ ^ [@] }msx ) {

                            # Add plugin
                            $dzil_dev_req->add_minimum( $package_name, $version );
                            next SECTION;
                        }

                        if ( $package_name ne __PACKAGE__ ) {

                            # Add bundle
                            $dzil_dev_req->add_minimum( $package_name, $version );
                            next SECTION;
                        }

                        # Add expanded bundle

                        # Bundles inside the bundle are expanded automatically, because
                        # BundleInfo loads the bundle through the official API.
                        my $bundle = Dist::Zilla::Util::BundleInfo->new(
                            bundle_name    => $section->{package},
                            bundle_payload => $section->{lines},
                        );

                      PLUGIN:
                        for my $plugin ( $bundle->plugins ) {
                            $package_name = $plugin->module;
                            next PLUGIN if exists $dzil_bundle_package{$package_name};

                            # payload_list calls _autoexpand_list which is broken and fails
                            # if a value is a code ref, we have to create the list ourself
                            my $plugin_payload = $plugin->payload;
                            my @payload_list;
                          KEY:
                            for my $key ( sort keys %{$plugin_payload} ) {
                                my $value = $plugin_payload->{$key};
                                if ( ref $value eq ref sub { } ) {
                                    push @payload_list, $key, $value;
                                }
                                else {
                                    push @payload_list, $plugin->_autoexpand_list( $key, $value );
                                }
                            }

                            $version = _get_version_from_section( \@payload_list );
                            $dzil_req->add_minimum( $package_name, $version );
                        }
                    }

                    # ref $cpanfile_project_prereqs = "CPAN::Meta::Prereqs"
                    # ref $dzil_req                 = "CPAN::Meta::Requirements"

                    if ($self_build) {
                        $cpanfile_project_prereqs = $cpanfile_project_prereqs->with_merged_prereqs(
                            CPAN::Meta::Prereqs->new(
                                {
                                    runtime => { requires => $dzil_req->as_string_hash },
                                    develop => { requires => $dzil_dev_req->as_string_hash },
                                },
                            ),
                        );
                    }

                    my $cpanfile_str = Module::CPANfile->from_prereqs( $cpanfile_project_prereqs->as_string_hash )->to_string;

                    if ( !$self_build ) {
                        $cpanfile_str .= "feature 'dzil', 'Dist::Zilla' => sub {\n";
                        $cpanfile_str .= Module::CPANfile->from_prereqs(
                            {
                                develop => { requires => $dzil_req->clone->add_requirements($dzil_dev_req)->as_string_hash },
                            },
                        )->to_string;
                        $cpanfile_str .= "};\n";
                    }

                    path( $self->zilla->root )->child('cpanfile')->spew($cpanfile_str);
                },
            },
        ],
    );

    # Remove double-declared entries from the cpanfile in the project
    $self->add_plugins('Author::SKIRMESS::CPANFile::Project::Sanitize');

    # Check at build/release time if modules are out of date
    $self->add_plugins(
        [
            'Author::SKIRMESS::PromptIfStale::CPANFile::Project',
            {
                phase => 'build',
            },
        ],
    );

    # check that the copyright year is correct
    $self->add_plugins('Author::SKIRMESS::CheckCopyrightYear');

    # check that the distribution contains only the correct files
    my @required_files = qw(
      Changes
      CONTRIBUTING
      LICENSE
      Makefile.PL
      MANIFEST
      META.json
      META.yml
      README
    );

    $self->add_plugins(
        [
            'Author::SKIRMESS::CheckFilesInDistribution',
            {
                required_file => \@required_files,
            },
        ],
    );

    # Automatically convert POD to a README in any format for Dist::Zilla
    $self->add_plugins( [ 'ReadmeAnyFromPod', 'ReadmeAnyFromPod/ReadmeTextInBuild' ] );

    # remove whitespace at end of line
    $self->add_plugins(
        [
            'Code::FileMunger',
            'RemoveWhitespaceFromEndOfLine',
            {
                munge_file => sub {
                    my ( $self, $file ) = @_;

                    return if $file->name ne 'README';

                    my $content = $file->content;
                    $content =~ s{ [ \t]+ \n }{\n}xsmg;
                    $file->content($content);

                    return;
                },
            },
        ],
    );

    $self->add_plugins(
        [
            'Code::LicenseProvider',
            {
                provide_license => sub {
                    my ( $self, $args ) = @_;

                    my $zilla = $self->zilla;

                    if ( $zilla->{_license_class} ne 'ISC' ) {
                        $self->log( colored( 'License is not ISC', 'red' ) );
                        return;
                    }

                    return Local::Software::License::ISC->new(
                        {
                            holder => $args->{copyright_holder},
                            year   => $args->{copyright_year},
                        },
                    );
                },
            },
        ],
    );

    # Add the license and vim line to all pm and pl files that are included
    # in the distribution. Additionally, the perl files are reformatted to
    # start with perl version, strict and warnings, then the package.
    $self->add_plugins(
        [
            'Code::FileMunger',
            'AddLicenseToDistFiles',
            {
                ':version' => '0.007',
                munge_file => sub {
                    my ( $self, $file ) = @_;

                    my $name = $file->name;

                    # skip the top level files like README or LICENSE
                    return if path($name)->basename eq $name;

                    # skip everything under corpus
                    return if path('corpus')->subsumes($name);

                    $self->log_fatal("Unknown file: $name")
                      if $name !~ m{ \A .+ [.] (?: pl | pm ) \z }xsm
                      && $name !~ m{ [^/] [.] pod \z }xsm
                      && $name !~ m{ \A x?t / .+ \Q.t\E \z }xsm
                      && $name !~ m{ \A bin / [^/]+ \z }xsm;

                    # Files should either be OnDist or InMemory
                    $self->log_fatal( q{'} . $file->name . q{' is not a 'Dist::Zilla::File::OnDisk'} . ' but a ' . blessed($file) ) if !$file->isa('Dist::Zilla::File::OnDisk') && !$file->isa('Dist::Zilla::File::InMemory');

                    $self->log_debug( [ 'Adding/updating license in %s', $file->name ] );

                    my $content =
                      ( $name =~ m{ [^/] [.] pod \z }xsm )
                      ? _add_license_to_pod_file( $self, $name, $file->content )
                      : _add_license_to_perl_file( $self, $name, $file->content );
                    $file->content($content);

                    return;
                },
            },
        ],
    );

    # Output a LICENSE file
    $self->add_plugins('License');

    # build an CONTRIBUTING file
    $self->add_plugins('Author::SKIRMESS::ContributingGuide');

    # Install a directory's contents as executables
    $self->add_plugins('ExecDir');

    # Install a directory's contents as "ShareDir" content
    $self->add_plugins('ShareDir');

    # Build a Makefile.PL that uses ExtUtils::MakeMaker
    # (this is also the test runner)
    $self->add_plugins(
        [
            'Author::SKIRMESS::MakeMaker::Awesome',
            {
                test_file        => 't/*.t',
                extended_prereqs => sub { return $extended_requires },
            },
        ],
    );

    # Support running xt tests via dzil test from the project
    $self->add_plugins(
        [
            'Author::SKIRMESS::RunExtraTests::FromProject',
            {
                skip_project => [
                    qw(
                      xt/author/clean-namespaces.t
                      xt/author/minimum_version.t
                      xt/author/perlcritic.t
                      xt/author/pod-no404s.t
                      xt/author/pod-spell.t
                      xt/author/pod-syntax.t
                      xt/author/portability.t
                      xt/author/test-version.t
                      xt/release/changes.t
                      xt/release/distmeta.t
                      xt/release/kwalitee.t
                      xt/release/manifest.t
                      xt/release/meta-json.t
                      xt/release/meta-yaml.t
                    ),
                ],
            },
        ],
    );

    # build a MANIFEST file
    $self->add_plugins('Manifest');

    # Remove generated by from MANIFEST to reduce churn
    $self->add_plugins(
        [
            'Code::FileMunger',
            'Manifest/NoChurn',
            {
                ':version' => '0.007',

                # we can't use munge_file because the MANIFEST file is of
                # type 'bytes'
                munge_files => sub {
                    my ($self) = @_;

                    my @files = grep { $_->name eq 'MANIFEST' } @{ $self->zilla->files };

                    $self->log_fatal(q{File 'MANIFEST' not found}) if !@files;
                    $self->log_fatal(q{Multiple 'MANIFEST' found}) if @files > 1;

                    my ($file) = @files;
                    $self->log_fatal( [ q{File '%s' is of type 'bytes'}, $file->name ] ) if !$file->is_bytes;

                    my $orig_coderef = $file->code();
                    $file->code(
                        sub {
                            $self->log_debug( [ 'Removing churn from %s', $file->name ] );
                            my $content = join "\n", grep { $_ !~ m{ ^ [#] }xsm } split /\n/, $file->$orig_coderef;    ## no critic (RegularExpressions::ProhibitUselessTopic, RegularExpressions::RequireDotMatchAnything, RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching)
                            return "$content\n";
                        },
                    );
                },
            },
        ],
    );

    # Check that you're on the correct branch before release
    $self->add_plugins('Git::CheckFor::CorrectBranch');

    # Ensure META includes resources
    $self->add_plugins('CheckMetaResources');

    # Prevent a release if you have prereqs not found on CPAN
    $self->add_plugins('CheckPrereqsIndexed');

    # Ensure Changes has content before releasing
    $self->add_plugins('CheckChangesHasContent');

    # Check if your distribution declares a dependency on itself
    $self->add_plugins('CheckSelfDependency');

    # Extract archive and run tests before releasing the dist
    $self->add_plugins('TestRelease');

    # Retrieve count of outstanding RT and github issues for your distribution
    $self->add_plugins('CheckIssues');

    # Prompt for confirmation before releasing
    $self->add_plugins('ConfirmRelease');

    # Upload the dist to CPAN
    $self->add_plugins('UploadToCPAN');

    # copy all files from the distribution to the project (after build and release)
    my @files_to_not_copy_back = qw(Changes MANIFEST);
    if ($self_build) {
        push @files_to_not_copy_back, qw(
          CONTRIBUTING
          Makefile.PL
          META.json
          META.yml
          README
        );
    }

    $self->add_plugins(
        [
            'Author::SKIRMESS::CopyAllFilesFromDistributionToProject',
            {
                skip_file => \@files_to_not_copy_back,
            },
        ],
    );

    # Commit dirty files
    $self->add_plugins(
        [
            'Git::Commit',
            {
                commit_msg  => '%v',
                allow_dirty => [
                    'Changes',
                    @generated_files,
                ],
                allow_dirty_match => [qw( \.pm$ \.pod$ ^bin/ )],
            },
        ],
    );

    # Tag the new version
    $self->add_plugins(
        [
            'Git::Tag',
            {
                tag_format  => '%v',
                tag_message => q{},
            },
        ],
    );

    # Push current branch
    $self->add_plugins('Git::Push');

    # Compare data and files at different phases of the distribution build process
    # listed last, to be sure we run at the very end of each phase
    $self->add_plugins('VerifyPhases');

    return;
}

sub _add_license_to_perl_file {
    my ( $plugin, $name, $content ) = @_;

    my @lines = split /\n/, $content;    ## no critic (RegularExpressions::RequireDotMatchAnything, RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching)

    # save shebang
    my $shebang;
    if ( $lines[0] =~ m{ \A [#] [!] }xsm ) {
        $shebang = shift @lines;
    }

    my $package;
    my $perl_version;
    my $perl_version_seen;
    my $strict_seen;
    my $warnings_seen;
    my $generated_msg;
  LINE:
    while (@lines) {

        # save the automatically generated message
        if ( $lines[0] =~ m{ \A [#] \Q Automatically generated file; DO NOT EDIT.\E \z }xsm ) {
            $plugin->log_fatal("Multiple generated messages: $generated_msg and $lines[0]") if defined $generated_msg;
            $generated_msg = shift @lines;
            next LINE;
        }

        # remove empty lines and comments at the beginning
        if ( $lines[0] =~ m{ \A (?: \s* \z | [#] ) }xsm ) {
            shift @lines;
            next LINE;
        }

        # keep everything as it is after use strict, warnings, and 5.???
        last LINE if $perl_version_seen && $strict_seen && $warnings_seen;

        # remove the package line
        if ( $lines[0] =~ m{ \A package \s }xsm ) {
            $plugin->log_fatal("Unexpected multiple package lines: $package and $lines[0]") if defined $package;
            $package = shift @lines;
            next LINE;
        }

        # remove use strict
        if ( $lines[0] =~ m{ \A use \s+ strict \s* ; \z }xsm ) {
            $strict_seen = 1;
            shift @lines;
            next LINE;
        }

        # remove use warnings
        if ( $lines[0] =~ m{ \A use \s+ warnings \s* ; \z }xsm ) {
            $warnings_seen = 1;
            shift @lines;
            next LINE;
        }

        # remove use 5.???
        if ( $lines[0] =~ m{ \A use \s+ 5 [.] }xsm ) {
            $plugin->log_fatal("Unexpected multiple Perl version lines: $perl_version and $lines[0]") if defined $perl_version;
            $perl_version_seen = 1;
            $perl_version      = shift @lines;
            next LINE;
        }

        # this should never be reaches as we don't expect anything special in
        # our files before use strict, warnings, 5.???, and the package declaration
        $plugin->log_fatal("Unexpected line: $lines[0]");
    }

    # looks like the file isn't as we expected it
    $plugin->log_fatal("cannot parse file $name: perl version declaration not seen") if !$perl_version_seen;
    $plugin->log_fatal("cannot parse file $name: strict not seen")                   if !$strict_seen;
    $plugin->log_fatal("cannot parse file $name: warnings not seen")                 if !$warnings_seen;

    # if the last line is a vim line, remove it
    if ( $lines[-1] =~ m{ \A [#] \s+ vim: }xsm ) {
        pop @lines;
    }

    # remove empty lines at the end
    while ( @lines && $lines[-1] =~ m{ \A \s* \z }xsm ) {
        pop @lines;
    }

    # create the new file
    my @content;

    # we start with the shebang, if it exists
    if ( defined $shebang ) {
        push @content, $shebang, q{};
    }

    # next we add a new vim line
    push @content, '# vim: ts=4 sts=4 sw=4 et: syntax=perl', q{#};

    # the license
    my $license_text = $plugin->zilla->license->fulltext;
    $license_text =~ s{ ^ }{# }xsmg;
    $license_text =~ s{ ^ [#] \s* $ }{#}xsmg;
    chomp $license_text;
    push @content, $license_text, q{};

    # the perl version, strict, and warnings
    push @content, $perl_version, 'use strict;', 'use warnings;';

    # add the automatically generated message back
    if ( defined $generated_msg ) {
        push @content, q{}, $generated_msg;
    }

    # if we removed the package line, add that line back
    if ( defined $package ) {
        push @content, q{}, $package;
    }

    push @content, q{}, @lines, q{};

    my $result = join "\n", @content;
    return $result;
}

sub _add_license_to_pod_file {
    my ( $plugin, $name, $content ) = @_;

    my @lines = split /\n/, $content;    ## no critic (RegularExpressions::RequireDotMatchAnything, RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching)

  LINE:
    while (@lines) {

        # remove empty lines and comments at the beginning
        if ( $lines[0] =~ m{ \A (?: \s* \z | [#] ) }xsm ) {
            shift @lines;
            next LINE;
        }

        # keep everything as it is after =pod
        last LINE if $lines[0] eq '=pod';

        # this should never be reaches as we don't expect anything special in
        # our files before use strict, warnings, 5.???, and the package declaration
        $plugin->log_fatal("Unexpected line: $lines[0]");
    }

    # remove empty lines at the end
    while ( @lines && $lines[-1] =~ m{ \A \s* \z }xsm ) {
        pop @lines;
    }

    # create the new file
    my @content;

    # next we add a new vim line
    push @content, '# vim: ts=2 sts=2 sw=2 et: syntax=perl', q{#};

    # the license
    my $license_text = $plugin->zilla->license->fulltext;
    $license_text =~ s{ ^ }{# }xsmg;
    $license_text =~ s{ ^ [#] \s* $ }{#}xsmg;
    chomp $license_text;
    push @content, $license_text, q{}, @lines, q{};

    my $result = join "\n", @content;
    return $result;
}

sub _attribute_from_payload {
    my ( $self, $payload ) = @_;

    return $self->config_slice($payload)->{$payload};
}

sub _find_files_extra_tests_files {
    my ($self) = @_;

    return if !-d 'xt';

    my $it = path('xt')->iterator( { recurse => 1 } );

    my @files;
  FILE:
    while ( defined( my $file = $it->() ) ) {
        next FILE if !-f $file;
        next FILE if $file !~ m{ [.] (?: t | pm ) $ }xsm;

        push @files, Dist::Zilla::File::OnDisk->new( { name => $file->absolute->stringify } );
    }

    return \@files;
}

sub _get_version_from_section {

    #my ( $self, $lines_ref ) = @_;
    my ($lines_ref) = @_;

    my $version = 0;

  LINE:
    for my $line_ref ( pairs @{$lines_ref} ) {
        my ( $key, $value ) = @{$line_ref};
        next LINE unless $key eq ':version';
        $version = $value;
    }

    return $version;
}

sub log {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ( $self, $msg ) = @_;

    my $name = $self->name;
    my $log  = sprintf '[%s] %s', $name, $msg;
    warn "$log\n";

    return;
}

sub log_fatal {
    my ( $self, $msg ) = @_;

    $self->log($msg);
    confess $msg;
}

sub _tempfile {
    my ($self) = @_;

    state @temp_files_to_remove_on_program_exit;

    push @temp_files_to_remove_on_program_exit, File::Temp->new( UNLINK => 1 );
    return "$temp_files_to_remove_on_program_exit[-1]";
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::PluginBundle::Author::SKIRMESS - Dist::Zilla configuration the way SKIRMESS does it

=head1 VERSION

Version 1.000

=head1 SYNOPSIS

=head2 Create a new dzil project

Create a new repository on Github, clone it, and add the following to
F<dist.ini>:

  [Git::Checkout]
  repo = https://github.com/skirmess/perl-dzil-bundle.git
  push_url = git@github.com:skirmess/perl-dzil-bundle.git
  dir = dzil-bundle

  [lib]
  lib = dzil-bundle/lib

  [@Author::SKIRMESS]
  :version = 1.000

=head1 DESCRIPTION

This is a L<Dist::Zilla|Dist::Zilla> PluginBundle.

The bundle will not be released on CPAN, instead it is designed to be
used with the Git::Checkout plugin in the project that will use it.

=head1 USAGE

This PluginBundle supports the following option:

=over 4

=item *

C<set_script_shebang> - This indicates whether C<SetScriptShebang> should be
used or not. (default: true)

=back

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/skirmess/perl-dzil-bundle/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/skirmess/perl-dzil-bundle>

  git clone https://github.com/skirmess/perl-dzil-bundle.git

=head1 AUTHOR

Sven Kirmess <sven.kirmess@kzone.ch>

=cut

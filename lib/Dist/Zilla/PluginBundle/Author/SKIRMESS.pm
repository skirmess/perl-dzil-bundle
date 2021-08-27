package Dist::Zilla::PluginBundle::Author::SKIRMESS;

use 5.010;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose 0.99;

with qw(
  Dist::Zilla::Role::PluginBundle::Easy
  Dist::Zilla::Role::PluginBundle::Config::Slicer
);

use Carp qw(confess);
use CPAN::Meta::Prereqs       ();
use CPAN::Meta::Requirements  ();
use Dist::Zilla::File::OnDisk ();
use Dist::Zilla::Types 6.000 qw(Path);
use Dist::Zilla::Util                    ();
use Dist::Zilla::Util::BundleInfo        ();
use Dist::Zilla::Util::ExpandINI::Reader ();
use File::Temp                           ();
use JSON::PP                             ();
use List::Util qw(pairs);
use Module::CPANfile 1.1004 ();
use Module::Metadata ();
use Path::Tiny qw(path);
use Perl::Critic::MergeProfile ();
use Scalar::Util qw(blessed);
use YAML::Tiny qw();

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
                exclude_match    => '^xt/(?!smoke/)',
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
    #   :ExtraTestFiles -> ^xt/ (only smoke tests in our case)
    $self->add_plugins('AutoPrereqs');

    # Detects the minimum version of Perl required for your dist
    $self->add_plugins('Author::SKIRMESS::MinimumPerl');

    # Smoker prereqs (xt/smoke) are added as develop dependencies by
    # AutoPrereqs above - save them to a variable because we need them for
    # the Makefile.PL.
    my $smoker_requires;
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
                    $smoker_requires = $cpan_meta_requirements->as_string_hash;

                    return;
                },
            },
        ],
    );

    # :ExtraTestFiles contains only the xt/smoke tests, or is empty, because
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
    #   :ExtraTestFiles -> ^xt/ (only smoke tests in our case)
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

                            # force this to be numeric - for whatever reason YAML::Tiny
                            # converts it to a string otherwise
                            if ( exists $meta_yaml->[0]->{dynamic_config} ) {
                                $meta_yaml->[0]->{dynamic_config} = $meta_yaml->[0]->{dynamic_config} + 0;
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
                    # cpanfile. The dependencies for xt/smoker, xt/author,
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

                    # Find all packages in the bundle
                    my @bundle_packages = sort keys %{ Module::Metadata->package_versions_from_directory( $_bundle_checkout_path->child('lib')->stringify ) };

                    # The bundles to expand (the SKIRMESS bundle)
                    my %bundle_to_expand = map { $_ => 1 } grep { m{ ^ Dist :: Zilla :: PluginBundle :: }xsm } @bundle_packages;

                    # Plugins to not depend on because they are in the bundle
                    my %skip = map { $_ => 1 } grep { !m{ ^ Dist :: Zilla :: PluginBundle :: }xsm } @bundle_packages;

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
                        next SECTION if exists $skip{$package_name};

                        if ( $section->{package} !~ m{ ^ [@] }msx ) {

                            # Add plugin
                            $dzil_dev_req->add_minimum( $package_name, $version );
                            next SECTION;
                        }

                        if ( !exists $bundle_to_expand{$package_name} ) {

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
                            next PLUGIN if exists $skip{$package_name};

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

    # Output a LICENSE file
    $self->add_plugins('License');

    # build an CONTRIBUTING file
    $self->add_plugins('Author::SKIRMESS::ContributingGuide');

    # Install a directory's contents as executables
    $self->add_plugins('ExecDir');

    # Install a directory's contents as "ShareDir" content
    $self->add_plugins('ShareDir');

    # Set dynamic_config to true in META.* files if we have smoker prereqs
    $self->add_plugins(
        [
            'Code::MetaProvider',
            {
                metadata => sub {
                    my ($self) = @_;
                    if ( keys %{$smoker_requires} ) {
                        return +{ dynamic_config => 1 };
                    }

                    return +{};
                },
            },
        ],
    );

    # Build a Makefile.PL that uses ExtUtils::MakeMaker
    # (this is also the test runner)
    $self->add_plugins(
        [
            'Author::SKIRMESS::MakeMaker::Awesome',
            {
                test_file        => 't/*.t',
                extended_prereqs => sub { return $smoker_requires },
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

    # Check your repo for merge-conflicted files
    $self->add_plugins('Git::CheckFor::MergeConflicts');

    # Ensure META includes resources
    $self->add_plugins('CheckMetaResources');

    # Prevent a release if you have prereqs not found on CPAN
    $self->add_plugins('CheckPrereqsIndexed');

    # Ensure Changes has content before releasing
    $self->add_plugins('CheckChangesHasContent');

    # Check if your distribution declares a dependency on itself
    $self->add_plugins('CheckSelfDependency');

    # BeforeRelease plugin to check for a strict version number
    $self->add_plugins(
        [
            'CheckStrictVersion',
            {
                decimal_only => 1,
            },
        ],
    );

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

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017-2021 by Sven Kirmess.

This is free software, licensed under:

  The (two-clause) FreeBSD License

=cut

# vim: ts=4 sts=4 sw=4 et: syntax=perl

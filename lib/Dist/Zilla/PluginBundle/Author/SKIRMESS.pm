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
use Dist::Zilla::File::OnDisk ();
use Dist::Zilla::Types 6.000 qw(Path);
use File::Temp ();
use Module::CPANfile 1.1004 ();
use Module::Metadata ();
use Path::Tiny qw(path);
use Perl::Critic::MergeProfile;

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

    # Check at build/release time if modules are out of date
    $self->add_plugins(
        [
            'PromptIfStale', 'PromptIfStale / CPAN::Perl::Releases',
            {
                phase  => 'build',
                module => [qw(CPAN::Perl::Releases)],
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

    # :ExtraTestFiles is empty because we don't add xt test files to the
    # distribution, that's why we have to create a new ExtraTestFiles
    # plugin
    #
    # code must be a single value but inside an array ref. Bug is
    # reported as:
    # https://github.com/rjbs/Config-MVP/issues/13
    $self->add_plugins(
        [
            'FinderCode', 'ExtraTestFiles',
            {
                code  => [ \&_find_files_extra_tests_files ],
                style => 'list',
            },
        ],
    );

    # automatically extract prereqs from your modules
    $self->add_plugins(
        [
            'AutoPrereqs',
            {
                develop_finder => ['@Author::SKIRMESS/ExtraTestFiles'],    ## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
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

    # Set script shebang to #!perl
    if ( $self->set_script_shebang ) {
        $self->add_plugins('SetScriptShebang');
    }

    # Detects the minimum version of Perl required for your dist
    $self->add_plugins('Author::SKIRMESS::MinimumPerl');

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

    # Extract namespaces/version from traditional packages for provides
    $self->add_plugins('MetaProvides::Package');

    # Extract namespaces/version from traditional packages for provides
    #
    # This adds packages found in scripts under bin which are skipped
    # by the default finder of MetaProvides::Package above.
    $self->add_plugins(
        [
            'MetaProvides::Package', 'MetaProvides::Package/ExecFiles',
            {
                meta_noindex => 1,
                finder       => ':ExecFiles',
            },
        ],
    );

    # Produce a META.yml
    $self->add_plugins('MetaYAML');

    # Produce a META.json
    $self->add_plugins('MetaJSON');

    # Remove develop prereqs from META.json file
    $self->add_plugins('Author::SKIRMESS::MetaJSON::RemoveDevelopPrereqs');

    # create a cpanfile in the project
    $self->add_plugins('Author::SKIRMESS::CPANFile::Project');

    # Add Dist::Zilla authordeps prereqs as develop dependencies with
    # feature dzil to the cpanfile in the project
    my $cpanfile_feature             = 'dzil';
    my $cpanfile_feature_description = 'Dist::Zilla';
    my $bundle_lib_dir               = $self->_bundle_checkout_path->child('lib');
    my @bundle_packages              = sort keys %{ Module::Metadata->package_versions_from_directory($bundle_lib_dir) };
    $self->add_plugins(
        [
            'Author::SKIRMESS::CPANFile::Project::Prereqs::AuthorDeps',
            {
                expand_bundle => [ grep { m{ ^ Dist :: Zilla :: PluginBundle :: }xsm } @bundle_packages ],
                skip          => [ grep { !m{ ^ Dist :: Zilla :: PluginBundle :: }xsm } @bundle_packages ],
                (
                    $self_build
                    ? ()
                    : (
                        feature             => $cpanfile_feature,
                        feature_description => $cpanfile_feature_description,
                    ),
                ),
            },
        ],
    );

    if ( !$self_build ) {

        # Save runtime dependencies of bundle to a temporary file which will be
        # used by Author::SKIRMESS::CPANFile::Project::Merge to add these
        # dependencies to develop/dzil dependencies of the project cpanfile
        my $bundle_cpanfile                 = $self->_bundle_checkout_path->child('cpanfile');
        my $cpanfile_obj                    = Module::CPANfile->load($bundle_cpanfile);
        my $runtime_prereqs                 = $cpanfile_obj->prereqs->as_string_hash->{runtime};
        my $bundle_runtime_prereqs_cpanfile = $self->_tempfile();
        Module::CPANfile->from_prereqs( { develop => $runtime_prereqs } )->save($bundle_runtime_prereqs_cpanfile);

        # merge a cpanfile into the cpanfile in the project
        $self->add_plugins(
            [
                'Author::SKIRMESS::CPANFile::Project::Merge',
                {
                    source              => $bundle_runtime_prereqs_cpanfile,
                    feature             => $cpanfile_feature,
                    feature_description => $cpanfile_feature_description,
                },
            ],
        );

    }

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
            'Author::SKIRMESS::RemoveWhitespaceFromEndOfLine',
            {
                file => [qw(README)],
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
                test_file => 't/*.t',
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

    # Build a MANIFEST file
    $self->add_plugins('Manifest');

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
        next FILE if $file !~ m{ [.] t $ }xsm;

        push @files, Dist::Zilla::File::OnDisk->new( { name => $file->absolute->stringify } );
    }

    return \@files;
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

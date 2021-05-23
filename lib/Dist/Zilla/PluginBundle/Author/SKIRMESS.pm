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
use CHI              ();
use CPAN::Meta::YAML ();
use CPAN::Perl::Releases qw(perl_versions);
use Dist::Zilla::File::OnDisk ();
use Dist::Zilla::Types 6.000 qw(Path);
use Dist::Zilla::Util::CurrentCmd qw(is_build);
use File::HomeDir ();
use File::Spec    ();
use File::Temp qw(tempfile);
use HTTP::Tiny ();
use JSON::MaybeXS qw(decode_json);
use Module::CPANfile 1.1004 ();
use Module::Metadata ();
use Path::Tiny qw(path);
use Perl::Critic::MergeProfile;
use Term::ANSIColor qw(colored);
use Text::Template qw(fill_in_file fill_in_string);
use version 0.77 ();

use namespace::autoclean 0.09;

# AppVeyor
use constant APPVEYOR_CONFIG_FILE         => '.appveyor.yml';
use constant APPVEYOR_AUTHOR_TESTING_PERL => qw(5.24);

# The directory which contains the bundle project if this not a self build.
use constant BUNDLE_DIR => 'dzil-inc';

# Text to mention that a file is automatically generated.
use constant GENERATED_TEXT => 'Automatically generated file; DO NOT EDIT.';

use constant PERL_CRITIC_CONFIG_FILE => 'xt/author/perlcriticrc';

use constant STRAWBERRY_PERL_RELEASES_URL => 'http://strawberryperl.com/releases.json';

# Template files copied from the submodule to the project
use constant TEMPLATE_FILES => qw(
  .perltidyrc
  .xtfilesrc
  xt/author/clean-namespaces.t
  xt/author/comment-spell.t
  xt/author/dependency-version.t
  xt/author/json-tidy.t
  xt/author/minimum-version.t
  xt/author/mojibake.t
  xt/author/no-tabs.t
  xt/author/perlcritic.t
  xt/author/perlcriticrc
  xt/author/perltidy.t
  xt/author/pod-linkcheck.t
  xt/author/pod-links.t
  xt/author/pod-spell.t
  xt/author/pod-syntax.t
  xt/author/portability.t
  xt/author/test-version.t
  xt/release/changes.t
  xt/release/distmeta.t
  xt/release/eol.t
  xt/release/kwalitee.t
  xt/release/manifest.t
  xt/release/meta-json.t
  xt/release/meta-yaml.t
);

# Text::Template delimiter
use constant TEXT_TEMPLATE_DELIM => [qw(  {{  }}  )];

# Travis CI
use constant TRAVIS_CI_AUTHOR_TESTING_PERL => qw(5.24);
use constant TRAVIS_CI_CONFIG_FILE         => '.travis.yml';
use constant TRAVIS_CI_OSX_PERL            => qw(5.18);

# Strawberry Perl
use constant WITH_USE_64_BIT_INT    => 1;
use constant WITHOUT_USE_64_BIT_INT => 2;

has appveyor_earliest_perl => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('appveyor_earliest_perl') // $_[0]->ci_earliest_perl;
    },
    init_arg => undef,
);

has appveyor_test_on_cygwin => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('appveyor_test_on_cygwin') // 1;
    },
    init_arg => undef,
);

has appveyor_test_on_cygwin64 => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('appveyor_test_on_cygwin64') // 1;
    },
    init_arg => undef,
);

has appveyor_test_on_strawberry => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('appveyor_test_on_strawberry') // 1;
    },
    init_arg => undef,
);

# The earliest version of Perl to test on Travis CI and AppVeyor
has ci_earliest_perl => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('ci_earliest_perl') // '5.8';
    },
    init_arg => undef,
);

# Produce debug output. Unfortunately we cannot depend on the debug flag of
# Dist::Zilla because it doesn't exist yet.
#
# This flag is controlled through the dist.ini file.
has debug => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
        $_[0]->_attribute_from_payload('debug');
    },
    init_arg => undef,
);

# Does the project have a Makefile.PL
has _makefile_pl_exists => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub {
        $_[0]->_self_build() ? q{} : 1;
    },
    init_arg => undef,
);

# The project path of the current building project
has root => (
    is      => 'ro',
    isa     => Path,
    default => sub {
        Path::Tiny->cwd->absolute;
    },
    init_arg => undef,
);

# The Author::SKIRMESS plugin bundle is used to build other distributions
# with Dist::Zilla, but it is also used to build the dzil-inc repository
# itself. When the dzil-inc repository is built no distribution is
# created as this repository is only intended to be included as
# Git submodule by other distributions repositories.
#
# The _self_build attribute is used to disable some Dist:Zilla plugins
# that are only used in other distribution.
#
# If __FILE__ is inside lib/Dist/Zilla/PluginBundle/Author of the cwd we
# are run with Bootstrap::lib in the dzil-inc repository which means we
# are building the bundle. Otherwise we use the bundle to build another
# distribution.
#
# Note: This is not "lazy" because if we ever change the directory it would
# produce wrong results.
has _self_build => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub {
        -d 'lib/Dist/Zilla/PluginBundle/Author' && path('lib/Dist/Zilla/PluginBundle/Author')->realpath eq path(__FILE__)->parent()->realpath();
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

# The caching web user agent
has _ua => (
    is       => 'ro',
    lazy     => 1,
    builder  => '_build_ua',
    init_arg => undef,
);

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

sub configure {
    my ($self) = @_;

    if ( is_build() ) {

        # Prereqs::Plugins (others maybe too) parses the bundle manually which
        # causes configure to be called multiple times. We don't like that.

        state $count = 0;
        $count++;
        if ( $count > 1 ) {
            $self->log("'configure' called $count times - skipping the creation of project files.");
        }
        else {
            $self->log( colored( 'Updating project files', 'green' ) );
            $self->_update_project();
            $self->log( colored( 'Project files successfully updated', 'green' ) );
        }
    }

    my $self_build = $self->_self_build;

    my @generated_files = qw(
      cpanfile
      LICENSE
      README.md
      t/00-load.t
    );

    if ( !$self_build ) {
        push @generated_files, qw(
          CONTRIBUTING
          Makefile.PL
          META.json
          META.yml
          README
        );
    }

    my @bundle_packages = sort keys %{ Module::Metadata->package_versions_from_directory( $self_build ? 'lib' : 'dzil-inc/lib' ) };

    # Save runtime dependencies of dzil-inc to a temporary file which will be
    # used by Author::SKIRMESS::CPANFile::Project::Merge to add these
    # dependencies to develop/dzil dependencies of the project cpanfile
    my $dzil_inc_runtime_prereqs_cpanfile;
    if ( !$self_build ) {
        my $dzil_inc_cpanfile = path( $self->root )->child('dzil-inc/cpanfile');
        my $cpanfile_obj      = Module::CPANfile->load($dzil_inc_cpanfile);
        my $runtime_prereqs   = $cpanfile_obj->prereqs->as_string_hash->{runtime};
        ( undef, $dzil_inc_runtime_prereqs_cpanfile ) = tempfile();
        Module::CPANfile->from_prereqs( { develop => $runtime_prereqs } )->save($dzil_inc_runtime_prereqs_cpanfile);
    }

    my $cpanfile_feature             = 'dzil';
    my $cpanfile_feature_description = 'Dist::Zilla';

    $self->add_plugins(

        # Add contributor names from git to your distribution
        'Git::Contributors',

        # Gather all tracked files in a Git working directory
        [
            'Git::GatherDir',
            {
                ':version'       => '2.016',
                exclude_filename => [
                    qw(
                      COMPATIBILITY
                      dist.ini
                      xt/author/perlcriticrc-code
                      xt/author/perlcriticrc-tests
                      ),
                    TEMPLATE_FILES,
                    @generated_files,
                ],
                exclude_match    => '^xt/(.+/)?.+[.]config$',
                include_dotfiles => 1,
            },
        ],

        # Set the distribution version from your main module's $VERSION
        ( $self_build ? () : 'VersionFromMainModule' ),

        # Bump and reversion $VERSION on release
        [
            'ReversionOnRelease',
            {
                prompt => 1,
            },
        ],

        # Check at build/release time if modules are out of date
        [
            'PromptIfStale', 'PromptIfStale / CPAN::Perl::Releases',
            {
                phase  => 'build',
                module => [qw(CPAN::Perl::Releases)],
            },
        ],

        # Create the t/00-load.t test
        'Author::SKIRMESS::Test::Load',

        # update Pod with project specific defaults
        'Author::SKIRMESS::UpdatePod',

        # fix the file permissions in your Git repository with Dist::Zilla
        [
            'Git::FilePermissions',
            {
                perms => ['^bin/ 0755'],
            },
        ],

        # Enforce the correct line endings in your Git repository with Dist::Zilla
        'Git::RequireUnixEOL',

        # Update the next release number in your changelog
        (
            $self_build
            ? ()
            : [
                'NextRelease',
                {
                    format    => '%v  %{yyyy-MM-dd HH:mm:ss VVV}d',
                    time_zone => 'UTC',
                },
            ]
        ),

        # Prune stuff that you probably don't mean to include
        'PruneCruft',

        # Decline to build files that appear in a MANIFEST.SKIP-like file
        'ManifestSkip',

        # :ExtraTestFiles is empty because we don't add xt test files to the
        # distribution, that's why we have to create a new ExtraTestFiles
        # plugin
        #
        # code must be a single value but inside an array ref. Bug is
        # reported as:
        # https://github.com/rjbs/Config-MVP/issues/13
        [
            'FinderCode', 'ExtraTestFiles',
            {
                code  => [ \&_find_files_extra_tests_files ],
                style => 'list',
            },
        ],

        # automatically extract prereqs from your modules
        [
            'AutoPrereqs',
            {
                develop_finder => [ ':ExtraTestFiles', '@Author::SKIRMESS/ExtraTestFiles', ],    ## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
            },
        ],

        # automatically extract Perl::Critic policy prereqs
        [
            'AutoPrereqs::Perl::Critic', 'AutoPrereqs::Perl::Critic / code',
            {
                critic_config => $self->_create_merged_perlcriticrc('code'),
            },
        ],

        [
            'AutoPrereqs::Perl::Critic', 'AutoPrereqs::Perl::Critic / tests',
            {
                critic_config => $self->_create_merged_perlcriticrc('tests'),
            },
        ],

        # Set script shebang to #!perl
        ( $self->set_script_shebang ? 'SetScriptShebang' : () ),

        # Detects the minimum version of Perl required for your dist
        'Author::SKIRMESS::MinimumPerl',

        # Stop CPAN from indexing stuff
        (
            $self_build
            ? ()
            : [
                'MetaNoIndex',
                {
                    directory => [ qw(t xt), grep { -d } qw(corpus demo examples fatlib inc local perl5 share) ],
                },
            ]
        ),

        # Automatically include GitHub meta information in META.yml
        [
            'GithubMeta',
            {
                issues => 1,
            },
        ],

        # Automatically convert POD to a README in any format for Dist::Zilla
        [
            'ReadmeAnyFromPod',
            {
                type     => 'markdown',
                filename => 'README.md',
                location => 'root',
            },
        ],

        # Extract namespaces/version from traditional packages for provides
        'MetaProvides::Package',

        # Extract namespaces/version from traditional packages for provides
        #
        # This adds packages found in scripts under bin which are skipped
        # by the default finder of MetaProvides::Package above.
        [
            'MetaProvides::Package', 'MetaProvides::Package/ExecFiles',
            {
                meta_noindex => 1,
                finder       => ':ExecFiles',
            },
        ],

        # Produce a META.yml
        ( $self_build ? () : 'MetaYAML' ),

        # Produce a META.json
        ( $self_build ? () : 'MetaJSON' ),

        # Remove develop prereqs from META.json file
        ( $self_build ? () : 'Author::SKIRMESS::MetaJSON::RemoveDevelopPrereqs' ),

        # create a cpanfile in the project
        'Author::SKIRMESS::CPANFile::Project',

        # Add Dist::Zilla authordeps prereqs as develop dependencies with
        # feature dzil to the cpanfile in the project
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

        # merge a cpanfile into the cpanfile in the project
        (
            $self_build
            ? ()
            : [
                'Author::SKIRMESS::CPANFile::Project::Merge',
                {
                    source              => $dzil_inc_runtime_prereqs_cpanfile,
                    feature             => $cpanfile_feature,
                    feature_description => $cpanfile_feature_description,
                },
            ],
        ),

        # Remove double-declared entries from the cpanfile in the project
        'Author::SKIRMESS::CPANFile::Project::Sanitize',

        # Check at build/release time if modules are out of date
        [
            'Author::SKIRMESS::PromptIfStale::CPANFile::Project',
            {
                phase => 'build',
            },
        ],

        # check that the copyright year is correct
        'Author::SKIRMESS::CheckCopyrightYear',

        # check that the distribution contains only the correct files
        [
            'Author::SKIRMESS::CheckFilesInDistribution',
            {
                required_file => [
                    qw(LICENSE Makefile.PL MANIFEST README),
                    ( $self_build ? () : qw(Changes CONTRIBUTING META.json META.yml) ),
                ],
            },
        ],

        # Automatically convert POD to a README in any format for Dist::Zilla
        [ 'ReadmeAnyFromPod', 'ReadmeAnyFromPod/ReadmeTextInBuild' ],

        # remove whitespace at end of line
        (
            $self_build
            ? ()
            : [
                'Author::SKIRMESS::RemoveWhitespaceFromEndOfLine',
                {
                    file => [qw(README)],
                },
            ]
        ),

        # Output a LICENSE file
        'License',

        # build an CONTRIBUTING file
        ( $self_build ? () : 'Author::SKIRMESS::ContributingGuide' ),

        # Install a directory's contents as executables
        'ExecDir',

        # Install a directory's contents as "ShareDir" content
        'ShareDir',

        # Build a Makefile.PL that uses ExtUtils::MakeMaker
        'MakeMaker',

        # Support running xt tests via dzil test from the project
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

        # Build a MANIFEST file
        'Manifest',

        # Check that you're on the correct branch before release
        'Git::CheckFor::CorrectBranch',

        # Check your repo for merge-conflicted files
        'Git::CheckFor::MergeConflicts',

        # Ensure META includes resources
        'CheckMetaResources',

        # Prevent a release if you have prereqs not found on CPAN
        'CheckPrereqsIndexed',

        # Ensure Changes has content before releasing
        'CheckChangesHasContent',

        # Check if your distribution declares a dependency on itself
        'CheckSelfDependency',

        # BeforeRelease plugin to check for a strict version number
        [
            'CheckStrictVersion',
            {
                decimal_only => 1,
            },
        ],

        # Extract archive and run tests before releasing the dist
        'TestRelease',

        # Retrieve count of outstanding RT and github issues for your distribution
        'CheckIssues',

        # Prompt for confirmation before releasing
        'ConfirmRelease',

        # Upload the dist to CPAN
        'UploadToCPAN',

        # copy all files from the distribution to the project (after build and release)
        [
            'Author::SKIRMESS::CopyAllFilesFromDistributionToProject',
            {
                skip_file => [
                    qw(MANIFEST),
                    ( $self_build ? qw(Makefile.PL README) : qw(Changes) ),
                ],
            },
        ],

        # Commit dirty files
        [
            'Git::Commit',
            {
                commit_msg  => '%v',
                allow_dirty => [
                    qw(
                      Changes
                      ),
                    @generated_files,
                ],
                allow_dirty_match => [qw( \.pm$ \.pod$ ^bin/ )],
            },
        ],

        # Tag the new version
        [
            'Git::Tag',
            {
                tag_format  => '%v',
                tag_message => q{},
            },
        ],

        # Push current branch
        'Git::Push',

        # Compare data and files at different phases of the distribution build process
        # listed last, to be sure we run at the very end of each phase
        'VerifyPhases',
    );

    return;
}

sub _attribute_from_payload {
    my ( $self, $payload ) = @_;

    return $self->config_slice($payload)->{$payload};
}

sub _copy_files_from_submodule_to_project {
    my ($self) = @_;

    my @files = TEMPLATE_FILES;
    return if !@files;

    $self->log('Copy files from submodule to project');

    my $project_root = $self->root;
    my $root         = path(BUNDLE_DIR)->absolute($project_root);
    $self->log_fatal("root dir '$root' must exist") if !-d $root;

  FILE:
    for my $file (@files) {
        $self->log_fatal("File '$file' is not relative") if !path($file)->is_relative;

        my $content = $self->_fill_in_file( $root->child($file)->stringify );

        if ( !defined $content ) {
            $self->log_fatal("Filling in the template returned undef for file '$file': $Text::Template::ERROR");
        }

        my $target        = path($file)->absolute;
        my $target_parent = $target->parent;

        if ( !-d $target_parent ) {
            my $target_parent_relative = $target_parent->relative($project_root);
            $self->log_fatal("'$target_parent_relative' exists but is not a directory") if -e $target_parent;

            $self->log_debug("Creating dir '$target_parent_relative'");
            $target_parent->mkpath;
        }

        my $target_relative = $target->relative($project_root);
        $self->log_debug( "Creating file '$target_relative' from template '" . $root->child($file)->relative($project_root) . q{'} );

        $target->spew($content);
    }

    return;
}

sub _create_appveyor_config {
    my ($self) = @_;

    $self->log( 'Creating file ' . APPVEYOR_CONFIG_FILE . ' (AppVeyor config file)' );

    # https://github.com/rjbs/Data-UUID/issues/24
    # Create the c:\tmp directory because Data::UUID can't be built on
    # Windows without it.

    my $appveyor_yml = <<'APPVEYOR_YML';
# {{ $generated }}

skip_tags: true

environment:
  AUTOMATED_TESTING: 1
  TAR_OPTIONS: --warning=no-unknown-keyword

  matrix:
APPVEYOR_YML

    my $appveyor_perl_used = 0;

    if ( $self->appveyor_test_on_cygwin ) {
        $appveyor_perl_used = 1;
        $appveyor_yml .= <<'APPVEYOR_YML';
    - PERL_TYPE: cygwin
      AUTHOR_TESTING: 1

APPVEYOR_YML
    }

    if ( $self->appveyor_test_on_cygwin64 ) {
        $appveyor_perl_used = 1;
        $appveyor_yml .= <<'APPVEYOR_YML';
    - PERL_TYPE: cygwin64
      AUTHOR_TESTING: 1

APPVEYOR_YML
    }

    if ( $self->appveyor_test_on_strawberry ) {

        ## no critic (RegularExpressions::RequireDotMatchAnything)
        ## no critic (RegularExpressions::RequireExtendedFormatting)
        ## no critic (RegularExpressions::RequireLineBoundaryMatching)
        my $auth_regex = join q{|}, map { qr{^\Q$_\E(?:[.].+)?$} } APPVEYOR_AUTHOR_TESTING_PERL();

        for my $strawberry_ref ( $self->_relevant_strawberry_perl_versions_for_appveyor ) {
            $appveyor_perl_used = 1;
            my ( $perl, $url ) = @{$strawberry_ref};

            $appveyor_yml .= <<"APPVEYOR_YML";
    - PERL_TYPE: strawberry
      PERL_VERSION: $perl
APPVEYOR_YML

            if ( $perl =~ $auth_regex ) {
                $appveyor_yml .= "      AUTHOR_TESTING: 1\n";
            }

            $appveyor_yml .= "      STRAWBERRY_URL: $url\n";
            $appveyor_yml .= "\n";
        }
    }

    $self->log_fatal('No Perl enabled for AppVeyor') if !$appveyor_perl_used;

    $appveyor_yml .= <<'APPVEYOR_YML';
install:
  - ps: 'Write-Host "ERROR: Unknown Perl type ''$env:PERL_TYPE''"'
  - exit 1

for:
APPVEYOR_YML

    if ( $self->appveyor_test_on_cygwin ) {
        $appveyor_yml .= <<'APPVEYOR_YML';
  -
    matrix:
      only:
        - PERL_TYPE: cygwin

    install:
      - c:\cygwin\setup-x86.exe -q -C devel -C perl -P libcrypt-devel -P libssl-devel
      - set PATH=C:\cygwin\bin;C:\cygwin\usr\local\bin;%PATH%

APPVEYOR_YML
    }

    if ( $self->appveyor_test_on_cygwin64 ) {
        $appveyor_yml .= <<'APPVEYOR_YML';
  -
    matrix:
      only:
        - PERL_TYPE: cygwin64

    install:
      - c:\cygwin64\setup-x86_64.exe -q -C devel -C perl -P libcrypt-devel -P libssl-devel
      - set PATH=C:\cygwin64\bin;C:\cygwin64\usr\local\bin;%PATH%

APPVEYOR_YML
    }

    if ( $self->appveyor_test_on_strawberry ) {
        $appveyor_yml .= <<'APPVEYOR_YML';
  -
    matrix:
      only:
        - PERL_TYPE: strawberry

    install:
      - ps: Invoke-WebRequest $env:STRAWBERRY_URL -OutFile strawberry.zip
      - ps: Expand-Archive strawberry.zip -DestinationPath c:\Strawberry
      - if exist c:\Strawberry\relocation.pl.bat c:\Strawberry\relocation.pl.bat
      - erase strawberry.zip
      - set PATH=C:\Strawberry\perl\site\bin;C:\Strawberry\perl\bin;C:\Strawberry\c\bin;%PATH%

APPVEYOR_YML
    }

    $appveyor_yml .= <<'APPVEYOR_YML';
before_build:
  - mv c:\mingw-w64 c:\mingw-w64.old
  - mv c:\mingw c:\mingw.old
  - ps: systeminfo | Select-String "^OS Name", "^OS Version"
  - where perl
  - perl -V
  - ps: Invoke-WebRequest https://raw.githubusercontent.com/skirmess/dzil-inc/master/bin/check-ci-perl-version -OutFile check-ci-perl-version.pl
  - perl check-ci-perl-version.pl --appveyor
  - erase check-ci-perl-version.pl
  - ps: $env:make = perl -MConfig -e'print $Config{make}'
  - echo %make%
  - if not exist %make% where %make%
  - where gcc
  - gcc --version
  - where g++
  - g++ --version
  - ps: Invoke-WebRequest https://cpanmin.us/ -OutFile cpanm.pl
  - perl cpanm.pl App::cpanminus
  - erase cpanm.pl
  - where cpanm
  - perl -S cpanm --version
  - mkdir C:\tmp
  - if     defined AUTHOR_TESTING perl -S cpanm --verbose --installdeps --notest --with-develop .
  - if not defined AUTHOR_TESTING perl -S cpanm --verbose --installdeps --notest .
  - perl -S cpanm --verbose --notest App::ReportPrereqs
  - if     defined AUTHOR_TESTING perl -S report-prereqs --with-develop
  - if not defined AUTHOR_TESTING perl -S report-prereqs

build_script:
  - set PERL_USE_UNSAFE_INC=0
APPVEYOR_YML

    if ( $self->_makefile_pl_exists() ) {
        $appveyor_yml .= <<'APPVEYOR_YML';
  - perl Makefile.PL
  - '%make%'
APPVEYOR_YML
    }

    $appveyor_yml .= <<'APPVEYOR_YML';

test_script:
APPVEYOR_YML

    $appveyor_yml .= $self->_makefile_pl_exists()
      ? <<'APPVEYOR_YML'
  - '%make% test'
APPVEYOR_YML
      : <<'APPVEYOR_YML';
  - prove -lr t
APPVEYOR_YML

    $appveyor_yml .= <<'APPVEYOR_YML';
  - if defined AUTHOR_TESTING perl -S prove -lr xt/author
APPVEYOR_YML

    path( APPVEYOR_CONFIG_FILE() )->spew( $self->_fill_in_string($appveyor_yml) );

    return;
}

sub _create_merged_perlcriticrc {
    my ( $self, $test_type ) = @_;

    return 'xt/author/perlcriticrc' if !-f "xt/author/perlcriticrc-$test_type";

    my $merge = Perl::Critic::MergeProfile->new;
    $merge->read('xt/author/perlcriticrc');
    $merge->read("xt/author/perlcriticrc-$test_type");

    my ( undef, $rc_file ) = tempfile();
    $merge->write($rc_file) or $self->_log_fatal("Cannot write merged Perl::Critic profile to $rc_file: $!");

    return $rc_file;
}

sub _create_perlcriticrc {
    my ($self) = @_;

    $self->log( 'Creating file ' . PERL_CRITIC_CONFIG_FILE() . ' (perlcritic config file)' );

    my $content = <<'PERLCRITICRC_TEMPLATE';
# {{ $generated }}

only = 1
profile-strictness = fatal
severity = 1
verbose = [%p] %m at %f line %l, near '%r'\n
PERLCRITICRC_TEMPLATE

    my $it = $self->_perl_critic_config_block;
    while ( defined( my $line = $it->() ) ) {
        $content .= $line;
    }

    path(PERL_CRITIC_CONFIG_FILE)->spew( $self->_fill_in_string($content) );

    return;
}

sub _create_travis_ci_config {
    my ($self) = @_;

    $self->log( 'Creating file ' . TRAVIS_CI_CONFIG_FILE() . ' (Travis CI config file)' );

    my $travis_yml = <<'TRAVIS_YML';
# {{ $generated }}

language: perl

cache:
  directories:
    - ~/perl5

env:
  global:
    - AUTOMATED_TESTING=1
    - TAR_OPTIONS=--warning=no-unknown-keyword

git:
  submodules: false

matrix:
  include:
TRAVIS_YML

    my %auth;
    @auth{ TRAVIS_CI_AUTHOR_TESTING_PERL() } = ();

    my %osx_perl;
    @osx_perl{ TRAVIS_CI_OSX_PERL() } = ();

    my $perl_helper_used = 0;

  PERL:
    for my $perl ( $self->_relevant_perl_versions_for_travis_ci ) {
        my @os = (undef);
        if ( exists $osx_perl{$perl} ) {
            push @os, 'osx';
        }

        for my $os (@os) {
            $travis_yml .= "    - perl: '$perl'\n";

            # Ubuntu 16.04 (xenial) does not have Perl <= 5.20 images
            my $dist = 'xenial';

            if ( $perl =~ m{ ^ 5 [.] ( [1-9][0-9]* ) $ }xsm ) {
                if ( $1 <= 20 ) {

                    # Ubuntu 14.04 (trusty) has all Perl versions
                    $dist = 'trusty';
                }
            }

            if ( $perl =~ m{ ^ 5 [.] ( [1-9][0-9]* ) [.] ( [0-9]+ ) $ }xsm ) {
                $perl_helper_used = 1;
            }

            my @env;
            if ( ( exists $auth{$perl} ) or ( defined $os ) ) {
                push @env, 'AUTHOR_TESTING=1';
            }

            if (@env) {
                $travis_yml .= '      env: ' . join( q{ }, @env ) . "\n";
            }

            if ( defined $os ) {
                $travis_yml .= "      os: $os\n";
                $dist = undef;
            }

            if ( defined $dist ) {
                $travis_yml .= "      dist: '$dist'\n";
            }

            $travis_yml .= "\n";
        }
    }

    $travis_yml .= <<'TRAVIS_YML';
before_install:
  - |
    case "${TRAVIS_OS_NAME}" in
      "linux" )
        ;;
      "osx"   )
        # TravisCI extracts the broken perl archive with sudo which creates the
        # $HOME/perl5 directory with owner root:staff. Subdirectories under
        # perl5 are owned by user travis.
        sudo chown "$USER" "$HOME/perl5"

        # The perl distribution TravisCI extracts on OSX is incomplete
        sudo rm -rf "$HOME/perl5/perlbrew"

        # Install cpanm and local::lib
        curl -L https://cpanmin.us | perl - App::cpanminus local::lib
        eval $(perl -I $HOME/perl5/lib/perl5/ -Mlocal::lib)
        ;;
    esac
TRAVIS_YML

    if ($perl_helper_used) {
        $travis_yml .= <<'TRAVIS_YML';
  - |
    if [[ $TRAVIS_PERL_VERSION =~ 5[.][1-9][0-9]*[.][0-9][0-9]* ]]
    then
        echo "Initializing the Travis Perl Helper"

        if [ -z "$AUTHOR_TESTING" ]
        then
            AUTHOR_TESTING=0
        fi

        git clone git://github.com/travis-perl/helpers ~/travis-perl-helpers
        source ~/travis-perl-helpers/init
        build-perl

        if [ "$AUTHOR_TESTING" = 0 ]
        then
            unset AUTHOR_TESTING
        fi
    fi
TRAVIS_YML

    }

    $travis_yml .= <<'TRAVIS_YML';
  - which perl
  - perl -V
  - curl -L https://raw.githubusercontent.com/skirmess/dzil-inc/master/bin/check-ci-perl-version | perl - --travis
  - which make
  - which gcc
  - gcc --version
  - which cpanm
  - cpanm --version

install:
  - |
    if [ -n "$AUTHOR_TESTING" ]
    then
        cpanm --verbose --installdeps --notest --with-develop .
    else
        cpanm --verbose --installdeps --notest .
    fi
  - cpanm --verbose --notest App::ReportPrereqs
  - |
    if [ -n "$AUTHOR_TESTING" ]
    then
        report-prereqs --with-develop
    else
        report-prereqs
    fi

script:
  - PERL_USE_UNSAFE_INC=0
TRAVIS_YML

    $travis_yml .=
      $self->_makefile_pl_exists()
      ? "  - perl Makefile.PL && make test\n"
      : "  - prove -lr t\n";

    $travis_yml .= <<'TRAVIS_YML';
  - |
    if [ -n "$AUTHOR_TESTING" ]
    then
        prove -lr xt/author
    fi
TRAVIS_YML

    path( TRAVIS_CI_CONFIG_FILE() )->spew( $self->_fill_in_string($travis_yml) );

    return;
}

sub _fill_in_file {
    my ( $self, $filename ) = @_;

    my %config = (
        plugin    => \$self,
        generated => GENERATED_TEXT(),
    );

    my $content = fill_in_file(
        $filename,
        BROKEN     => sub { my %hash = @_; $self->log_fatal( $hash{error} ); },
        DELIMITERS => TEXT_TEMPLATE_DELIM,
        STRICT     => 1,
        HASH       => \%config,
    );

    return $content;
}

sub _fill_in_string {
    my ( $self, $string ) = @_;

    my %config = (
        plugin    => \$self,
        generated => GENERATED_TEXT(),
    );

    my $content = fill_in_string(
        $string,
        BROKEN     => sub { my %hash = @_; $self->log_fatal( $hash{error} ); },
        DELIMITERS => TEXT_TEMPLATE_DELIM,
        STRICT     => 1,
        HASH       => \%config,
    );

    return $content;
}

sub log {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ( $self, $msg ) = @_;

    my $name = $self->name;
    my $log  = sprintf '[%s] %s', $name, $msg;
    warn "$log\n";

    return;
}

sub log_debug {
    my ( $self, $msg ) = @_;

    if ( $self->debug ) {
        $self->log($msg);
    }

    return;
}

sub log_fatal {
    my ( $self, $msg ) = @_;

    $self->log($msg);
    confess $msg;
}

# Returns an iterator that iterates over all policies of all the perlcritic
# policy distributions we use. Return value is a string containing the
# configuration of one policy, or a comment block.
#
# The returned string are expected to be concatenated together to create
# the perlcriticrc config file.
sub _perl_critic_config_block {
    my ($self) = @_;

    my $it = $self->_perl_critic_policy_default_config;

    my $last_dist = q{};
    my $pol_ref;
    my $empty_line = 0;
    return sub {
        if ( !defined $pol_ref ) {
            $pol_ref = $it->();
        }

        return if !defined $pol_ref;

        my ( $dist, $policy, $enabled, $config_ref ) = @{$pol_ref};

        if ( $dist ne $last_dist ) {

            # we have to return the dist "header"
            $last_dist = $dist;

            my $result = $empty_line ? q{} : "\n";
            $result .= '# ' . ( q{-} x 58 ) . "\n";
            $result .= ( $dist eq 'Perl::Critic' ? "# Core policies\n" : "# $dist\n" );
            $result .= '# ' . ( q{-} x 58 ) . "\n\n";

            $empty_line = 1;

            return $result;
        }

        $pol_ref = undef;

        my $result = "[$policy]\n";

        if ( !$enabled ) {
            $empty_line = 0;
            return "#$result";
        }

        if ( !defined $config_ref ) {
            $empty_line = 0;
            return $result;
        }

        if ( !$empty_line ) {
            $result = "\n$result";
        }

        for my $key ( sort keys %{$config_ref} ) {
            $result .= "$key = ${$config_ref}{$key}\n";
        }

        $empty_line = 1;
        return "$result\n";

    };
}

# Returns an iterator that iterates over all policies of all the perlcritic
# policy distributions we use. Return value is an array ref of the
# distribution name and the policy name.
sub _perl_critic_policy {
    my ($self) = @_;

    my $dist_it = $self->_perl_critic_policy_distributions;
    my $dist;
    my $pol_it;

    return sub {
        if ( defined $pol_it ) {
            my $pol = $pol_it->();
            return [ $dist, $pol ] if defined $pol;
        }

        $dist = $dist_it->();
        return if !defined $dist;

        $pol_it = $self->_perl_critic_policy_from_distribution($dist);
        my $pol = $pol_it->();
        return [ $dist, $pol ] if defined $pol;
        return;
    };
}

# Returns an iterator that iterates over all policies of all the perlcritic
# policy distributions we use. Return value is an array ref of the
# distribution name, the policy name, if the policy should be enabled and
# either undef or a hash ref of default configuration for that policy.
#
# This method contains a list a default configurations we like.
sub _perl_critic_policy_default_config {
    my ($self) = @_;

    my $it = $self->_perl_critic_policy_default_enabled;

    return sub {
        my $pol_ref = $it->();
        return if !defined $pol_ref;

        my $policy = $pol_ref->[1];

        push @{$pol_ref},

          # Core Policies
            $policy eq 'ErrorHandling::RequireCarping' ? { allow_in_main_unless_in_subroutine => '1' }
          : $policy eq 'InputOutput::RequireCheckedSyscalls' ? { functions => ':builtins', exclude_functions => 'exec print say sleep' }
          : $policy eq 'Modules::ProhibitEvilModules' ? { modules => 'Class::ISA {Found use of Class::ISA. This module is deprecated by the Perl 5 Porters.} Pod::Plainer {Found use of Pod::Plainer. This module is deprecated by the Perl 5 Porters.} Shell {Found use of Shell. This module is deprecated by the Perl 5 Porters.} Switch {Found use of Switch. This module is deprecated by the Perl 5 Porters.} Readonly {Found use of Readonly. Please use constant.pm or Const::Fast.} base {Found use of base. Please use parent instead.} File::Slurp {Found use of File::Slurp. Please use Path::Tiny instead.} common::sense {Found use of common::sense. Please use strict and warnings instead.} Class::Load {Found use of Class::Load. Please use Module::Runtime instead.} Any::Moose {Found use of Any::Moose. Please use Moo instead.} Error {Found use of Error.pm. Please use Throwable.pm instead.} Getopt::Std {Found use of Getopt::Std. Please use Getopt::Long instead.} HTML::Template {Found use of HTML::Template. Please use Template::Toolkit.} IO::Socket::INET6 {Found use of IO::Socket::INET6. Please use IO::Socket::IP.} JSON {Found use of JSON. Please use JSON::MaybeXS or Cpanel::JSON::XS.} JSON::XS {Found use of JSON::XS. Please use JSON::MaybeXS or Cpanel::JSON::XS.} JSON::Any {Found use of JSON::Any. Please use JSON::MaybeXS.} List::MoreUtils {Found use of List::MoreUtils. Please use List::Util or List::UtilsBy.} Mouse {Found use of Mouse. Please use Moo.} Net::IRC {Found use of Net::IRC. Please use POE::Component::IRC, Net::Async::IRC, or Mojo::IRC.} XML::Simple {Found use of XML::Simple. Please use XML::LibXML, XML::TreeBuilder, XML::Twig, or Mojo::DOM.} Sub::Infix {Found use of Sub::Infix. Please do not use it.} vars {the vers pragma has been superseded by our declarations, available in Perl v5.6.0 or later, and use of this pragma is discouraged.}' }
          : $policy eq 'Subroutines::ProhibitUnusedPrivateSubroutines' ? { private_name_regex => '_(?!build_)\w+' }
          : $policy eq 'ValuesAndExpressions::ProhibitComplexVersion'  ? { forbid_use_version => '1' }

          # Perl::Critic::Moose
          : $policy eq 'Moose::ProhibitDESTROYMethod' ? { equivalent_modules => 'Moo Moo::Role' }
          : $policy eq 'Moose::ProhibitLazyBuild'     ? { equivalent_modules => 'Moo Moo::Role' }
          : $policy eq 'Moose::ProhibitMultipleWiths' ? { equivalent_modules => 'Moo Moo::Role' }
          : $policy eq 'Moose::ProhibitNewMethod'     ? { equivalent_modules => 'Moo Moo::Role' }

          # Perl::Critic::Policy::Variables::ProhibitUnusedVarsStricter
          : $policy eq 'Variables::ProhibitUnusedVarsStricter' ? { allow_unused_subroutine_arguments => '1' }
          :                                                      undef;

        return $pol_ref;
    };
}

# Returns an iterator that iterates over all policies of all the perlcritic
# policy distributions we use. Return value is an array ref of the
# distribution name, the policy name and if the policy should be enabled.
#
# This method has a blacklist of policies we don't like. They get disabled.
#
# This method has another blacklist of policies that are no policies,
# basically badly named packages. They get completely dropped.
sub _perl_critic_policy_default_enabled {
    my ($self) = @_;

    my %disabled_policies = map { $_ => 0 } (

        # core policies
        'CodeLayout::RequireTidyCode',
        'Documentation::PodSpelling',
        'Documentation::RequirePodSections',
        'InputOutput::RequireBriefOpen',
        'Modules::ProhibitExcessMainComplexity',
        'Modules::RequireVersionVar',
        'RegularExpressions::ProhibitComplexRegexes',
        'RegularExpressions::ProhibitEnumeratedClasses',
        'Subroutines::ProhibitExcessComplexity',
        'Subroutines::RequireArgUnpacking',
        'ValuesAndExpressions::ProhibitConstantPragma',
        'ValuesAndExpressions::ProhibitLeadingZeros',
        'ValuesAndExpressions::ProhibitMagicNumbers',
        'Variables::ProhibitPunctuationVars',

        # Perl::Critic::Bangs
        'Bangs::ProhibitCommentedOutCode',
        'Bangs::ProhibitNoPlan',
        'Bangs::ProhibitNumberedNames',
        'Bangs::ProhibitVagueNames',

        # Perl::Critic::Freenode
        'Freenode::EmptyReturn',

        # Perl::Critic::Itch
        'CodeLayout::ProhibitHashBarewords',

        # Perl::Critic::Lax
        'Lax::ProhibitEmptyQuotes::ExceptAsFallback',
        'Lax::ProhibitLeadingZeros::ExceptChmod',
        'Lax::ProhibitStringyEval::ExceptForRequire',
        'Lax::RequireConstantOnLeftSideOfEquality::ExceptEq',
        'Lax::RequireEndWithTrueConst',
        'Lax::RequireExplicitPackage::ExceptForPragmata',

        # Perl::Critic::More
        'CodeLayout::RequireASCII',
        'Editor::RequireEmacsFileVariables',
        'ErrorHandling::RequireUseOfExceptions',
        'ValuesAndExpressions::RequireConstantOnLeftSideOfEquality',
        'ValuesAndExpressions::RestrictLongStrings',

        # Perl::Critic::Pulp
        'CodeLayout::ProhibitIfIfSameLine',
        'Compatibility::Gtk2Constants',

        # Disable the Compatibility::PerlMinimumVersionAndWhy policy because
        # it injects stuff into the Perl::MinimumVersion module that causes
        # hard to debug problems.
        'Compatibility::PerlMinimumVersionAndWhy',
        'Compatibility::PodMinimumVersion',
        'Documentation::ProhibitDuplicateSeeAlso',
        'Documentation::RequireFinalCut',
        'Miscellanea::TextDomainPlaceholders',
        'Miscellanea::TextDomainUnused',
        'ValuesAndExpressions::ProhibitFiletest_f',

        # Perl::Critic::StricterSubs
        'Subroutines::ProhibitCallsToUndeclaredSubs',
        'Subroutines::ProhibitCallsToUnexportedSubs',

        # Perl::Critic::Tics
        'Tics::ProhibitLongLines',
    );

    my %policies_to_remove = map { $_ => 1 } (

        # This is no policy, just a badly named package!
        'Documentation::ProhibitAdjacentLinks::Parser',
    );

    my $it = $self->_perl_critic_policy;

    return sub {
        my $pol_ref;

      POL_REF:
        while (1) {
            $pol_ref = $it->();
            last POL_REF if !defined $pol_ref;
            last POL_REF if !exists $policies_to_remove{ $pol_ref->[1] };
        }

        if ( !defined $pol_ref ) {
          POLICY:
            for my $policy ( keys %disabled_policies ) {
                next POLICY if $disabled_policies{$policy} == 1;

                $self->log_fatal("Policy '$policy' is disabled but does not exist.");
            }

            return;
        }

        push @{$pol_ref}, exists $disabled_policies{ $pol_ref->[1] } ? 0 : 1;
        $disabled_policies{ $pol_ref->[1] } = 1;

        return $pol_ref;
    };
}

# Returns an iterator that iterates over the perlcritic policy distributions
# we use.
sub _perl_critic_policy_distributions {
    my ($self) = @_;

    my @stack = qw(
      Perl::Critic
      Perl::Critic::Bangs
      Perl::Critic::Freenode
      Perl::Critic::Itch
      Perl::Critic::Lax
      Perl::Critic::Moose
      Perl::Critic::More
      Perl::Critic::PetPeeves::JTRAMMELL
      Perl::Critic::Policy::BuiltinFunctions::ProhibitDeleteOnArrays
      Perl::Critic::Policy::BuiltinFunctions::ProhibitReturnOr
      Perl::Critic::Policy::HTTPCookies
      Perl::Critic::Policy::Moo::ProhibitMakeImmutable
      Perl::Critic::Policy::Perlsecret
      Perl::Critic::Policy::TryTiny::RequireBlockTermination
      Perl::Critic::Policy::TryTiny::RequireUse
      Perl::Critic::Policy::ValuesAndExpressions::PreventSQLInjection
      Perl::Critic::Policy::ValuesAndExpressions::ProhibitSingleArgArraySlice
      Perl::Critic::Policy::Variables::ProhibitLoopOnHash
      Perl::Critic::Policy::Variables::ProhibitUnusedVarsStricter
      Perl::Critic::Pulp
      Perl::Critic::StricterSubs
      Perl::Critic::Tics
    );

    return sub {
        return if !@stack;
        return shift @stack;
    };
}

# Returns an iterator that can be used to iterate over all the perlcritic
# policies in a policy distribution.
sub _perl_critic_policy_from_distribution {
    my ( $self, $distribution ) = @_;

    my $url = "http://cpanmetadb.plackperl.org/v1.0/package/$distribution";
    $self->log_debug("Downloading '$url'...");
    my $res = $self->_ua->get($url);

    $self->log_fatal("Cannot download '$url': $res->{reason}") if !$res->{success};

    my $yaml = CPAN::Meta::YAML->read_string( $res->{content} ) or $self->log_fatal( CPAN::Meta::YAML->errstr );
    my $meta = $yaml->[0];

    $self->log_fatal('Unable to parse returned data') if !exists $meta->{provides};

    my @policies;
  MODULE:
    for my $module ( keys %{ $meta->{provides} } ) {
        if ( $module =~ m{ ^ Perl::Critic::Policy:: ( .+ ) }xsm ) {
            push @policies, $1;
        }
    }

    my @stack = sort { lc $a cmp lc $b } @policies;

    return sub {
        return if !@stack;
        return shift @stack;
    };
}

sub _relevant_perl_5_8_versions_for_travis_ci {
    my ($self) = @_;

    my $earliest_perl = $self->ci_earliest_perl;
    return if version->parse("v$earliest_perl") >= version->parse('v5.9');

    $self->log_fatal('Perl 5.8.0 is not supported because cpanm does not work on 5.8.0') if $earliest_perl eq '5.8.0';
    $self->log_fatal("Perl $earliest_perl does not exist") if version->parse("v$earliest_perl") > version->parse('v5.8.9');

    return qw(5.8.1 5.8.2 5.8) if $earliest_perl eq '5.8' || $earliest_perl eq '5.8.1';
    return $earliest_perl, '5.8' if version->parse("v$earliest_perl") < version->parse('v5.8.8');

    return $earliest_perl;
}

sub _relevant_perl_5_10_versions_for_travis_ci {
    my ($self) = @_;

    my $earliest_perl = $self->ci_earliest_perl;
    return if version->parse("v$earliest_perl") >= version->parse('v5.11');

    $self->log_fatal("Perl $earliest_perl does not exist") if version->parse("v$earliest_perl") > version->parse('v5.10.1');

    return '5.10' if $earliest_perl eq '5.10.1';
    return qw(5.10.0 5.10);
}

# This generates a list of Perl versions I think are relevant to be tested on
# Travis CI. The list includes all stable versions of Perl, starting with
# 5.8, as major.minor entry. Additionally, the following versions are added:
#  - 5.8.0
#  - 5.8.1
#  - 5.8.2
#  - 5.10.0
sub _relevant_perl_versions_for_travis_ci {
    my ($self) = @_;

    my $earliest_perl = $self->ci_earliest_perl;

    # Generate the list of all stable versions of perl as major.minor,
    # starting with 5.12 (or the first version we are interested in).
    my %perl;
  PERL:
    for my $perl ( perl_versions() ) {
        next PERL if $perl !~ m { ^ 5 [.] ( [1-9][0-9]* ) [.] [0-9]+ $ }xsm;
        my $minor = $1;    ## no critic (RegularExpressions::ProhibitCaptureWithoutTest)

        # Remove dev releases
        next PERL if $minor % 2;

        next PERL if version->parse("v5.$minor") < version->parse("v$earliest_perl");
        next PERL if $minor < 12;

        # Allow us to skip the latest Perl if Travis hasn't it available yet
        if ( exists $ENV{TRAVIS_CI_LATEST_PERL} ) {
            if ( version->parse("v5.$minor") > version->parse("v$ENV{TRAVIS_CI_LATEST_PERL}") ) {
                $self->log("Skipping Perl 5.$minor on Travis");
                next PERL;
            }
        }

        $perl{$minor} = 1;
    }

    my @perls;

    if ( version->parse("v$earliest_perl") < version->parse('v5.11') ) {
        if ( version->parse("v$earliest_perl") < version->parse('v5.9') ) {
            @perls = $self->_relevant_perl_5_8_versions_for_travis_ci;
        }

        push @perls, $self->_relevant_perl_5_10_versions_for_travis_ci;
    }
    elsif ( $earliest_perl =~ m{ ^ 5 [.] ( [1-9][0-9]* ) [.] ( [0-9]+ ) $ }xsm ) {

        # if the earliest perl version has a patch level, add this version to
        # the versions to be tested but skip the major.minor from Travis for
        # this release. The _relevant_perl_5_8_versions_for_travis_ci and
        # _relevant_perl_5_10_versions_for_travis_ci method already does that
        # for these releases.

        @perls = "5.$1.$2";
    }

    # Add the releases >= 5.12 releases
    push @perls, map { "5.$_" } sort { $a <=> $b } keys %perl;

    return @perls;
}

sub _relevant_strawberry_perl_versions_for_appveyor_sort {
    my $x = version->parse("v$a->[2]") <=> version->parse("v$b->[2]");
    return $x if $x;

    if ( $a->[4] ne $b->[4] ) {
        return 1 if $a->[4] eq '64bit';
        return -1;
    }

    return $a->[5] <=> $b->[5];
}

sub _relevant_strawberry_perl_versions_for_appveyor {
    my ($self) = @_;

    my $earliest_perl = version->parse( 'v' . $self->appveyor_earliest_perl );
    my @strawberry_releases =
      reverse
      sort _relevant_strawberry_perl_versions_for_appveyor_sort grep { version->parse("v$_->[1]") >= $earliest_perl } @{ $self->_strawberry_releases() };

    my @strawberry_releases_to_use;
    my %perl_configured;
  RELEASE:
    for my $strawberry_ref (@strawberry_releases) {
        if ( $strawberry_ref->[0] eq '5.10' ) {
            next RELEASE if exists $perl_configured{ $strawberry_ref->[1] };
            $perl_configured{ $strawberry_ref->[1] } = 1;
        }
        else {
            next RELEASE if exists $perl_configured{ $strawberry_ref->[0] };
            $perl_configured{ $strawberry_ref->[0] } = 1;
        }

        push @strawberry_releases_to_use, $strawberry_ref;
    }

    return reverse map { [ $_->[1], $_->[3] ] } @strawberry_releases_to_use;
}

sub _strawberry_releases {
    my ($self) = @_;

    my $url = STRAWBERRY_PERL_RELEASES_URL;
    $self->log_debug("Downloading '$url'...");
    my $res = $self->_ua->get($url);

    $self->log_fatal("Cannot download '$url': $res->{reason}") if !$res->{success};

    my @releases;

  RELEASE:
    for my $release ( @{ decode_json( $res->{content} ) } ) {
        my $version = $release->{version};
        ## no critic (RegularExpressions::RequireDotMatchAnything)
        ## no critic (RegularExpressions::RequireExtendedFormatting)
        ## no critic (RegularExpressions::RequireLineBoundaryMatching)
        my @name = split /\s*\/\s*/, $release->{name};

        $self->log_fatal("Unable to parse name: $release->{name}")                 if ( @name < 3 ) || ( @name > 4 );
        $self->log_fatal("Version '$version' does not version in name '$name[1]'") if $version ne $name[1];
        $self->log_fatal("Unable to parse version '$version'")                     if $version !~ m{ ^ ( ( 5 [.] [1-9][0-9]* ) [.] [0-9]+ ) [.] [0-9]+ $ }xsm;

        my @release = ( $2, $1, $version );    ## no critic (RegularExpressions::ProhibitCaptureWithoutTest)

        next RELEASE if !exists $release->{edition}->{zip}->{url};
        push @release, $release->{edition}->{zip}->{url};

        if ( $name[2] eq '64bit' ) {
            push @release, $name[2];
        }
        elsif ( $name[2] eq '32bit' ) {
            push @release, $name[2];

            if ( $name[3] eq 'with USE_64_BIT_INT' ) {
                push @release, WITH_USE_64_BIT_INT;
            }
            elsif ( $name[3] eq 'without USE_64_BIT_INT' ) {
                push @release, WITHOUT_USE_64_BIT_INT;
            }
            else {
                $self->log_fatal("Expect either 'with USE_64_BIT_INT' or 'without USE_64_BIT_INT' but got '$name[3]'");
            }
        }
        else {
            $self->log_fatal("Expected either 32bit or 64bit but got '$name[2]'");
        }

        push @releases, \@release;
    }

    return \@releases;
}

sub _update_project {
    my ($self) = @_;

    $self->_create_appveyor_config;
    $self->_create_travis_ci_config;

    my $self_build = $self->_self_build;

    if ($self_build) {
        $self->_create_perlcriticrc;
    }
    else {
        $self->_copy_files_from_submodule_to_project;
    }

    return;
}

sub _build_ua {
    my ($self) = @_;

    my $ua = HTTP::Tiny->new;

    return $ua;
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

Create a new repository on Github and clone it.

  $ git submodule add ../dzil-inc.git
  $ git commit -m 'added Author::SKIRMESS plugin bundle as git submodule'

  # in dist.ini
  [lib]
  lib = dzil-inc/lib

  [@Author::SKIRMESS]
  :version = 1.000

=head2 Clone a project which already contains this submodule

  $ git clone https://github.com/skirmess/...
  $ git submodule update --init

  # To update dzil-inc
  $ cd dzil-inc && git checkout master


=head2 Update the submodule

  $ cd dzil-inc && git pull

=head1 DESCRIPTION

This is a L<Dist::Zilla|Dist::Zilla> PluginBundle.

The bundle will not be released on CPAN, instead it is designed to be
included as Git submodule in the project that will use it.

=head1 USAGE

To use this PluginBundle, include it as Git submodule in your project and
add it to your dist.ini. You can provide the following options:

=over 4

=item *

C<appveyor_earliest_perl> - Earliest version of Perl to use on AppVeyor.
(default: ci_earliest_perl)

=item *

C<appveyor_test_on_cygwin> - Test with Cygwin 32 bit on AppVeyor. (default:
true)

=item *

C<appveyor_test_on_cygwin64> - Test with Cygwin 64 bit on AppVeyor. (default:
true)

=item *

C<appveyor_test_on_strawberry> - Test with Strawberry Perl on AppVeyor.
(default: true)

=item *

C<ci_earliest_perl> - The earliest version of Perl to test on Travis CI and
AppVeyor. (default: 5.8)

=item *

C<debug> - Enables debug output of the Bundle itself (unfortunately the
status of C<dzil -v> is unknown to a plugin bundle). (default: false)

=item *

C<set_script_shebang> - This indicates whether C<SetScriptShebang> should be
used or not. (default: true)

=back

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at L<https://github.com/skirmess/dzil-inc/issues>.
You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.

L<https://github.com/skirmess/dzil-inc>

  git clone https://github.com/skirmess/dzil-inc.git

=head1 AUTHOR

Sven Kirmess <sven.kirmess@kzone.ch>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2017-2021 by Sven Kirmess.

This is free software, licensed under:

  The (two-clause) FreeBSD License

=cut

# vim: ts=4 sts=4 sw=4 et: syntax=perl

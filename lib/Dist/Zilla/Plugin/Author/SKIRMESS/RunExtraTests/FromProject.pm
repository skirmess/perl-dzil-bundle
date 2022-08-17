# vim: ts=4 sts=4 sw=4 et: syntax=perl
#
# Copyright (c) 2017-2022 Sven Kirmess
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

use 5.006;
use strict;
use warnings;

package Dist::Zilla::Plugin::Author::SKIRMESS::RunExtraTests::FromProject;

our $VERSION = '1.000';

use Moose;

with qw(
  Dist::Zilla::Role::BeforeBuild
  Dist::Zilla::Role::TestRunner
);

use App::Prove               ();
use Dist::Zilla::Types 6.000 qw(Path);
use File::pushd              ();
use Path::Tiny;

use namespace::autoclean;

sub mvp_multivalue_args { return (qw( skip_build skip_project )) }

has skip_build => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has skip_project => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has _project_root => (
    is  => 'rw',
    isa => Path,
);

sub before_build {
    my ($self) = @_;

    $self->_project_root( $self->zilla->root->absolute );

    return;
}

sub test {
    my ( $self, $target, $arg_ref ) = @_;

    # Fail if the dist hasn't been built yet
    $self->log_fatal(q{Distribution isn't built yet. Please ensure that you place 'RunExtraTests::FromRepository' after your other test runners (e.g. 'MakeMaker')}) if !-d 'blib';

    my $project_root  = $self->_project_root;
    my $prove_arg_ref = [ $self->_prove_arg($arg_ref) ];

    my @tests = $self->_xt_tests();

    my $path_to_project_root = path($project_root)->relative(q{.});
    my %skip_build           = map { $_ => 1 } @{ $self->skip_build };
    my @build_tests          = map { $path_to_project_root->child($_)->stringify } grep { !exists $skip_build{$_} } @tests;

    if ( !@build_tests ) {
        $self->log('No xt tests (from prohect) to run against the build');
    }
    else {
        local $ENV{BUILD_TESTING} = 1;
        local $ENV{PROJECT_TESTING};    ## no critic (Variables::RequireInitializationForLocalVars)
        delete $ENV{PROJECT_TESTING};

        $self->log('Running xt tests (from project) on build');
        $self->_run_prove( $prove_arg_ref, \@build_tests );
    }

    my %skip_project  = map  { $_ => 1 } @{ $self->skip_project };
    my @project_tests = grep { !exists $skip_project{$_} } @tests;

    if ( !@project_tests ) {
        $self->log('No xt tests (from project) to run against the project');
    }
    else {
        local $ENV{BUILD_TESTING};    ## no critic (Variables::RequireInitializationForLocalVars)
        delete $ENV{BUILD_TESTING};
        local $ENV{PROJECT_TESTING} = 1;

        my $wd = File::pushd::pushd($project_root);    ## no critic (Variables::ProhibitUnusedVarsStricter)

        $self->log('Running xt tests (from project) on project');
        $self->_run_prove( $prove_arg_ref, \@project_tests );
    }

    return;
}

sub _prove_arg {
    my ( $self, $arg_ref ) = @_;

    my @prove = qw( -b );

    my $verbose = $self->zilla->logger->get_debug;
    if ( defined $arg_ref && ref $arg_ref eq ref {} ) {
        if ( exists $arg_ref->{test_verbose} && $arg_ref->{test_verbose} ) {
            $verbose = 1;
        }

        if ( exists $arg_ref->{jobs} ) {
            push @prove, '-j', $arg_ref->{jobs};
        }
    }

    if ($verbose) {
        push @prove, '-v';
    }

    return @prove;
}

sub _run_prove {
    my ( $self, $prove_arg_ref, $tests_ref ) = @_;

    my @cmd = ( @{$prove_arg_ref}, @{$tests_ref} );

    local $ENV{XT_FILES_DEFAULT_CONFIG_FILE} = path( $self->_project_root )->child('.xtfilesrc')->stringify;

    my $app = App::Prove->new;
    $self->log_debug( [ 'running prove with args: %s', join q{ }, @cmd ] );
    $app->process_args(@cmd);
    $app->run or $self->log_fatal('Fatal errors in xt tests');

    return;
}

sub _xt_tests {
    my ($self) = @_;

    # check if the project root we saved during the before build phase exists
    my $project_root = $self->_project_root;
    $self->log_fatal('internal error: _project_root is not defined')                                       if !defined $project_root;
    $self->log_fatal("internal error: _project_root '$project_root' does not exist or is not a directory") if !-d $project_root;

    # Change to the project root (will be restored when $wd goes out of scope)
    my $wd = File::pushd::pushd($project_root);    ## no critic (Variables::ProhibitUnusedVarsStricter)

    # Find all the tests we have to run
    my @tests;
    my $it = path('xt')->iterator( { recurse => 1 } );

  FILE:
    while ( defined( my $file = $it->() ) ) {

        # not a file
        next FILE if !-f $file->stringify;

        # not a .t file
        next FILE if $file->basename !~ m{ [.] t $ }xsm;

        # extended test, e.g. xt/test-this.t
        next FILE if path('xt')->child( $file->basename )->stringify eq $file->stringify;

        # author test
        if ( path('xt')->child('author')->child( $file->basename )->stringify eq $file->stringify ) {
            if ( exists $ENV{AUTHOR_TESTING} || exists $ENV{DZIL_RELEASING} ) {
                push @tests, $file->stringify;
            }

            next FILE;
        }

        # release test
        if ( path('xt')->child('release')->child( $file->basename )->stringify eq $file->stringify ) {
            if ( exists $ENV{RELEASE_TESTING} || exists $ENV{DZIL_RELEASING} ) {
                push @tests, $file->stringify;
            }

            next FILE;
        }

        $self->log_fatal("Unknown test file '$file'");
    }

    @tests = sort { lc $a cmp lc $b } @tests;
    return @tests;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::RunExtraTests::FromProject - support running xt tests from your project via dzil test

=head1 VERSION

Version 1.000

=head1 SYNOPSIS

In your F<dist.ini>:

[Author::SKIRMESS::RunExtraTests::FromProject]

=head1 DESCRIPTION

This plugin is used to run xt tests from your project against your
distribution and against your project. This is useful if you do not want to
include your xt tests in your distribution. If you include your xt tests with
your distribution, use L<RunExtraTests|Dist::Zilla::Plugin::RunExtraTests>
instead.

The plugin was created because the existing test plugins always run the tests
from the build against the build. This makes it impossible to check files
that are part of your project but not included in the distribution which can
be useful for some tests. Additionally it forces you to include your author
tests in the distribution, which, in my opinion, is questionable because the
distribution is no longer a working dzil project anyway.

Runs xt tests when the test phase is run (e.g. dzil test, dzil release etc).
Tests from C<xt/release> and C<xt/author> will be tested based on the values
of the appropriate environment variables C<RELEASE_TESTING> and
C<AUTHOR_TESTING> which are set by dzil test. Only tests directly under
C<xt/author> and C<xt/release> are run, all other files are ignored.

All xt tests are run twice, once against the built distribution and again
against the project. The environment variable C<BUILD_TESTING> is set and
C<PROJECT_TESTING> is unset if the xt tests are run against the distribution.
When the xt tests are run against the project C<PROJECT_TESTING> is set and
C<BUILD_TESTING> is unset. If both variables are unset the test is most likely
run directly under prove.

C<Author::SKIRMESS::RunExtraTests::FromProject> must be listed after one of
the normal test-running plugins (e.g. MakeMaker).

=head2 skip_build

The option C<skip_build> is used to specify xt tests to skip while testing
the distribution. The option can be specified multiple times.

=head2 skip_project

The option C<skip_project> is used to specify xt tests to skip while testing
the project. The option can be specified multiple times.

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

=head1 SEE ALSO

L<Dist::Zilla|Dist::Zilla>,
L<Dist::Zilla::Plugin::RunExtraTests|Dist::Zilla::Plugin::RunExtraTests>

=cut

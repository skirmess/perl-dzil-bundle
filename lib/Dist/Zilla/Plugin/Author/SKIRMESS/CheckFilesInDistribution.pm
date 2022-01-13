package Dist::Zilla::Plugin::Author::SKIRMESS::CheckFilesInDistribution;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::AfterBuild);

use File::pushd;
use File::Spec;
use Path::Tiny;

use namespace::autoclean;

sub mvp_multivalue_args { return (qw( required_file )) }

has required_file => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

sub after_build {
    my ( $self, $data ) = @_;

    $self->log_fatal(q{'build_root' not defined}) if !exists $data->{build_root};

    my %required_file = map { $_ => 1 } @{ $self->required_file };

  FILE:
    for my $file ( $self->_get_files_in_archive( $data->{build_root} ) ) {
        if ( exists $required_file{$file} ) {
            delete $required_file{$file};
            next FILE;
        }

        $self->log_fatal("Unexpeted file '$file' in distribution.") if !$self->_is_file_allowed($file);
    }

    my @missing_files = keys %required_file;
    if (@missing_files) {
        $self->log_fatal("Required file '$missing_files[-1]' not in distribution");
    }

    $self->log_debug('Distribution is ok');

    return;
}

sub _get_files_in_archive {
    my ( $self, $built_in ) = @_;

    # change to the generated distribution
    my $wd = pushd($built_in);    ## no critic (Variables::ProhibitUnusedVarsStricter)

    my @files;
    my $it = path(q{.})->iterator( { recurse => 1 } );

  FILE:
    while ( defined( my $file = $it->() ) ) {
        next FILE if -d $file;

        $self->log_fatal("'$file' is not a file or directory") if -l $file || !-f _;

        push @files, $file->stringify;
    }

    return @files;
}

sub _is_file_allowed {
    my ( $self, $file_name ) = @_;

    my @dirs = File::Spec->splitdir($file_name);
    return if @dirs == 1;

    if ( $dirs[0] eq 'bin' ) {
        return 1 if $dirs[-1] !~ m{ .+ [.] pl $ }xsm;
        return;
    }

    if ( $dirs[0] eq 'lib' ) {
        return 1 if $dirs[-1] =~ m{ .+ [.] (?: pm | pod ) $ }xsm;
        return;
    }

    if ( $dirs[0] eq 't' ) {
        return 1 if $dirs[1] =~ m{ .+ [.] t $ }xsm;

        # t/lib/**/*.pm
        return 1 if @dirs > 2 && $dirs[1] eq 'lib' && $dirs[-1] =~ m{ .* [.] pm $ }xsm;

        return;
    }

    if ( $dirs[0] eq 'xt' ) {
        return 1 if $dirs[1] =~ m{ .+ [.] t $ }xsm;

        # xt/lib/**/*.pm
        return 1 if @dirs > 2 && $dirs[1] eq 'lib' && $dirs[-1] =~ m{ .* [.] pm $ }xsm;

        return;
    }

    return 1 if $dirs[0] eq 'corpus';

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CheckFilesInDistribution - check that the distribution contains only the correct files

=head1 VERSION

Version 1.000

=head1 SYNOPSIS

In your F<dist.ini>:

[Author::SKIRMESS::CheckFilesInDistribution]
required_file = LICENSE
required_file = Makefile.PL
required_file = ...

=head1 DESCRIPTION

This plugin runs after the build and checks that it contains only files we expect to include in a distribution. Additionally it checks that all C<required_file>s are included.

=head2 required_file

Specifies a file that must be included in the distribution. The file must be specified as full path without the C<dist_basename>.

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

This software is Copyright (c) 2017-2022 by Sven Kirmess.

This is free software, licensed under:

  The (two-clause) FreeBSD License

=cut

# vim: ts=4 sts=4 sw=4 et: syntax=perl

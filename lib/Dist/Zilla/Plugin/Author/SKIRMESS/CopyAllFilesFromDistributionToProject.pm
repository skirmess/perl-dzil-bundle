package Dist::Zilla::Plugin::Author::SKIRMESS::CopyAllFilesFromDistributionToProject;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(
  Dist::Zilla::Role::AfterBuild
  Dist::Zilla::Role::AfterRelease
);

use File::Compare;
use Path::Tiny;

use namespace::autoclean;

sub mvp_multivalue_args { return (qw( skip_file )) }

has skip_file => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

sub after_build {
    my ( $self, $data ) = @_;

    $self->log_fatal(q{'build_root' not defined}) if !exists $data->{build_root};

    return $self->_copy_all_files_back( $data->{build_root} );
}

sub after_release {
    my ($self) = @_;

    my $zilla    = $self->zilla;
    my $built_in = $zilla->ensure_built;

    return $self->_copy_all_files_back($built_in);
}

sub _copy_all_files_back {
    my ( $self, $src_dir ) = @_;

    my %skip = map { $_ => 1 } @{ $self->skip_file };

    $self->log_Fatal("Not a directory: $src_dir") if !-d $src_dir;

    $src_dir = path($src_dir);
    my $it = $src_dir->iterator( { recurse => 1 } );

  FILE:
    while ( defined( my $file = $it->() ) ) {
        next FILE if -d $file;

        my $target = $file->relative($src_dir);
        next FILE if exists $skip{$target};

        $self->log_fatal("File '$file' is not a regular file") if -l $file || !-f _;

        if ( -f $target ) {
            my $rc = compare( $file, $target );

            if ( $rc == 0 ) {
                $self->log_debug("File '$file' and '$target' are identical.");
                next FILE;
            }

            if ( $rc == -1 ) {
                $self->log_fatal("Unable to compare '$file' with '$target': $!");
            }
        }

        if ( !-d $target->parent ) {
            $target->parent->mkpath();
        }

        path($file)->copy($target);

        $self->log("Copy $file to $target");
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CopyAllFilesFromDistributionToProject - copy all files from the distribution into the project after build/release

=head1 VERSION

Version 1.000

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

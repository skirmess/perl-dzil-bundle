package Dist::Zilla::Plugin::Author::SKIRMESS::RemoveWhitespaceFromEndOfLine;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with 'Dist::Zilla::Role::FileMunger';

use Path::Tiny;

use namespace::autoclean;

sub mvp_multivalue_args { return (qw( file )) }

has file => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
);

sub munge_file {
    my ( $self, $file ) = @_;

    my %file;
    @file{ @{ $self->file } } = 1;

    # stringify returns the path standardized with Unix-style / directory
    # separators.
    return if !exists $file{ path( $file->name )->stringify() };

    my $content = $file->content;
    $content =~ s{ [ \t]+ \n }{\n}xsmg;
    $file->content($content);

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::RemoveWhitespaceFromEndOfLine - remove whitespace at end of line

=head1 VERSION

Version 1.000

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

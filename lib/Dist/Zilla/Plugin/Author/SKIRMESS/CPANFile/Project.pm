package Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::AfterBuild);

use Module::CPANfile 1.1004 ();
use Path::Tiny qw(path);

use namespace::autoclean;

has filename => (
    is      => 'ro',
    isa     => 'Str',
    default => 'cpanfile',
);

sub after_build {
    my ($self) = @_;

    my $zilla    = $self->zilla;
    my $prereqs  = $zilla->prereqs;
    my $pre      = $prereqs->as_string_hash;
    my $cpanfile = path( $zilla->root )->child( $self->filename )->stringify;

    Module::CPANfile->from_prereqs($pre)->save($cpanfile);

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project - create a cpanfile in the project

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

This software is Copyright (c) 2017-2021 by Sven Kirmess.

This is free software, licensed under:

  The (two-clause) FreeBSD License

=cut

# vim: ts=4 sts=4 sw=4 et: syntax=perl

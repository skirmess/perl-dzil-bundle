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

use 5.006;
use strict;
use warnings;

package Dist::Zilla::Plugin::Author::SKIRMESS::PromptIfStale::CPANFile::Project;

our $VERSION = '1.000';

use Moose;

with qw(
  Dist::Zilla::Role::AfterBuild
  Dist::Zilla::Role::BeforeRelease
);

extends qw(Dist::Zilla::Plugin::PromptIfStale);

use List::Util       qw(uniq);
use Module::CPANfile ();
use Path::Tiny       qw(path);

use namespace::autoclean;

has filename => (
    is      => 'ro',
    isa     => 'Str',
    default => 'cpanfile',
);

sub after_build {
    my ($self) = @_;

    return if $self->phase ne 'build';

    $self->_check_modules_from_cpanfile;

    return;
}

sub before_release {
    my ($self) = @_;

    return if $self->phase ne 'release';

    $self->_check_modules_from_cpanfile;

    return;
}

sub _check_modules_from_cpanfile {
    my ($self) = @_;

    my $zilla = $self->zilla;

    my $cpanfile = path( $zilla->root )->child( $self->filename );
    $self->log_fatal("cpanfile '$cpanfile' does not exist") if !-f $cpanfile;

    my $cpanfile_obj = Module::CPANfile->load($cpanfile);

    my $prereqs  = $cpanfile_obj->prereqs;
    my @features = $cpanfile_obj->features;
    if (@features) {
        $prereqs = $prereqs->with_merged_prereqs( map { $_->prereqs } @features );
    }

    my @phases = $prereqs->phases;
    my @types;
    for my $phase (@phases) {
        push @types, $prereqs->types_in($phase);
    }
    @types = uniq sort @types;

    my $req     = $prereqs->merged_requirements( \@phases, \@types );
    my @modules = sort $req->required_modules;

    return if !@modules;

    $self->_check_modules(@modules);

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::PromptIfStale::CPANFile::Project - Check at build/release time if modules are out of date

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

=cut

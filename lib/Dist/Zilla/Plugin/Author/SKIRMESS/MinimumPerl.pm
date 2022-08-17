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

package Dist::Zilla::Plugin::Author::SKIRMESS::MinimumPerl;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::PrereqSource);

use Perl::MinimumVersion 1.26;
use Safe::Isa;
use Term::ANSIColor qw(colored);

use namespace::autoclean;

sub register_prereqs {
    my ($self) = @_;

    $self->_scan_files( 'runtime',   ':InstallModules', ':ExecFiles' );
    $self->_scan_files( 'configure', ':IncModules' );
    $self->_scan_files( 'test',      ':TestFiles' );
    $self->_scan_files( 'develop',   ':ExtraTestFiles' );

    return;
}

sub _scan_files {
    my ( $self, $phase, @finder ) = @_;

    my %file;
    for my $finder (@finder) {
        for my $file ( @{ $self->zilla->find_files($finder) } ) {
            my $name = $file->name;
            $file{$name} = $file;
        }
    }

    my %pmv;
    for my $file_name ( keys %file ) {
        my $pmv = Perl::MinimumVersion->new( \$file{$file_name}->content );
        $self->log_fatal("Unable to parse $file_name") if !defined $pmv;

        $pmv{$file_name} = $pmv;
    }

    my $min_perl;
  FILE:
    for my $file_name ( keys %pmv ) {
        my $ver = $pmv{$file_name}->minimum_explicit_version;
        next FILE if !defined $ver || !$ver->$_isa('version');

        if ( !defined $min_perl || $ver > $min_perl ) {
            $min_perl = $ver;
            $self->log( "Requires Perl $min_perl for phase $phase because of explicit declaration in file " . $file_name );
        }
    }

  FILE:
    for my $file_name ( keys %pmv ) {
        my $ver = $pmv{$file_name}->minimum_syntax_version;
        next FILE if !defined $ver || !$ver->$_isa('version');

        if ( !defined $min_perl || $ver > $min_perl ) {
            $min_perl = $ver;
            $self->log( colored( "Requires Perl $min_perl for phase $phase because of syntax in file $file_name", 'red' ) );
        }
    }

    if ( defined $min_perl ) {
        $self->zilla->register_prereqs(
            { phase => $phase },
            'perl' => $min_perl,
        );

        # The MakeMaker plugin adds the highest Perl version for all phases
        # to the Makefile.PL script - which means this is the Perl version
        # required for the configure phase...
        $self->zilla->register_prereqs(
            { phase => 'configure' },
            'perl' => $min_perl,
        );
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::MinimumPerl - detects the minimum version of Perl required

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

package Dist::Zilla::Plugin::Author::SKIRMESS::MinimumPerl;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::PrereqSource);

use Perl::MinimumVersion 1.26;
use Term::ANSIColor qw(colored);

use namespace::autoclean;

sub register_prereqs {
    my ($self) = @_;

    $self->_scan_files( 'runtime', ':InstallModules', ':ExecFiles' );
    $self->_scan_files( 'configure', ':IncModules' );
    $self->_scan_files( 'test',      ':TestFiles' );

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
        next if !defined $ver;

        if ( !defined $min_perl || $ver > $min_perl ) {
            $min_perl = $ver;
            $self->log( "Requires Perl $min_perl for phase $phase because of explicit declaration in file " . $file_name );
        }
    }

  FILE:
    for my $file_name ( keys %pmv ) {
        my $ver = $pmv{$file_name}->minimum_syntax_version;

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

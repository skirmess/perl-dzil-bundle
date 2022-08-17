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

package Dist::Zilla::Plugin::Author::SKIRMESS::UpdatePod;

our $VERSION = '1.000';

use Moose;

with qw(
  Dist::Zilla::Role::Author::SKIRMESS::Resources
  Dist::Zilla::Role::FileMunger
);

use Path::Tiny;

use namespace::autoclean;

use constant REQUIRED  => 1;
use constant ALLOWED   => 2;
use constant FORBIDDEN => 3;

sub munge_file {
    my ( $self, $file ) = @_;

    my $filename = $file->name;

    # stringify returns the path standardized with Unix-style / directory
    # separators.
    return if path($filename)->stringify() !~ m{ ^ (?: bin | lib ) / }xsm;

    my $content = $file->content;

    # perl code must contain Pod
    $self->log_fatal("File '$filename' contains no Pod") if $content !~ m{ ^ =pod }xsm;

    # Check if the correct sections exist
    $self->_check_pod_sections($file);

    # VERSION
    $self->_update_pod_section_version($file);

    # SUPPORT
    $self->_update_pod_section_support($file);

    # AUTHOR
    $self->_update_pod_section_author($file);

    return;
}

sub _check_pod_sections {
    my ( $self, $file ) = @_;

    my @sections = grep { m{ ^ = head1 \s+ }xsm } split m{\n}xsm, $file->content;
    for my $section (@sections) {
        $section =~ s{ ^ =head1 \s+ }{}xsm;
    }

    my $is_lib = $file->name =~ m{ [.] pm $ }xsm;

    my @needed_sections = (
        [ 'NAME',                  REQUIRED ],
        [ 'VERSION',               REQUIRED ],
        [ 'SYNOPSIS',              ALLOWED ],
        [ 'DESCRIPTION',           ALLOWED ],
        [ 'USAGE',                 ( $is_lib ? ALLOWED   : FORBIDDEN ) ],
        [ 'OPTIONS',               ( $is_lib ? FORBIDDEN : ALLOWED ) ],
        [ 'SUBCOMMANDS',           ( $is_lib ? FORBIDDEN : ALLOWED ) ],
        [ 'EXIT STATUS',           ( $is_lib ? FORBIDDEN : ALLOWED ) ],
        [ 'EXAMPLES',              ALLOWED ],
        [ 'ENVIRONMENT',           ALLOWED ],
        [ 'RATIONALE',             ALLOWED ],
        [ 'SEE ALSO',              ALLOWED ],
        [ 'SUPPORT',               REQUIRED ],
        [ 'AUTHOR',                REQUIRED ],
        [ 'CONTRIBUTORS',          ALLOWED ],
        [ 'COPYRIGHT AND LICENSE', FORBIDDEN ],
    );

  SECTION:
    while ( @needed_sections && @sections ) {
        if ( $needed_sections[0][0] eq $sections[0] ) {
            if ( $needed_sections[0][1] != FORBIDDEN ) {
                shift @needed_sections;
                shift @sections;
                next SECTION;
            }

            $self->log_fatal( "Section '$sections[0]' found but is forbidden in '" . $file->name . q{'} );
        }

        if ( $needed_sections[0][1] != REQUIRED ) {
            shift @needed_sections;
            next SECTION;
        }

        $self->log_fatal( "Section '$sections[0]' either not allowed or in the wrong position in file '" . $file->name . q{'} );
    }

  NEEDED_SECTION:
    for my $section_ref (@needed_sections) {
        next NEEDED_SECTION if !@{$section_ref};
        next NEEDED_SECTION if $section_ref->[1] != REQUIRED;

        $self->log_fatal( "Required section '$section_ref->[0]' not found in '" . $file->name . q{'} ) if @needed_sections;
    }

    return;
}

sub _update_pod_section_author {
    my ( $self, $file ) = @_;

    my $filename = $file->name;
    my $content  = $file->content;

    my $section = "\n\n=head1 AUTHOR\n\n" . join( "\n", @{ $self->zilla->authors } ) . "\n\n";

    # remove old CONTRIBUTORS section, they will be added back after the AUTHORS section
    $content =~ s{
        [\s\n]*
        ^ =head1 \s+ CONTRIBUTORS [^\n]* $
        .*?
        ^ (?= = (?: head1 | cut ) )
    }{\n\n}xsm;

    my $contributors = $self->zilla->distmeta->{x_contributors};
    if ( defined $contributors ) {
        $section .= "=head1 CONTRIBUTORS\n\n=over\n\n";
        $section .= join "\n\n", map { "=item *\n\n$_" } @{$contributors};
        $section .= "\n\n=back\n\n";
    }

    if (
        $content !~ s{
            [\s\n]*
            ^ =head1 \s+ AUTHOR [^\n]* $
            .*?
            ^ (?= = (?: head1 | cut ) )
        }{$section}xsm
      )
    {
        $self->log_fatal("Unable to replace AUTHOR section in file $filename.");
    }

    $file->content($content);

    return;
}

sub _update_pod_section_support {
    my ( $self, $file ) = @_;

    my $filename = $file->name;
    my $content  = $file->content;

    my $bugtracker = $self->bugtracker;
    $self->log_fatal('distmeta does not contain bugtracker') if !defined $bugtracker;

    my $homepage = $self->homepage;
    $self->log_fatal('distmeta does not contain homepage') if !defined $homepage;

    my $repository = $self->repository;
    $self->log_fatal('distmeta does not contain repository') if !defined $repository;

    # We must protect this here-doc, otherwise we find the =head1 entries and
    # corrupt ourself.
    my $section = <<"SUPPORT_SECTION";
#
#
#=head1 SUPPORT
#
#=head2 Bugs / Feature Requests
#
#Please report any bugs or feature requests through the issue tracker
#at L<$bugtracker>.
#You will be notified automatically of any progress on your issue.
#
#=head2 Source Code
#
#This is open source software. The code repository is available for
#public review and contribution under the terms of the license.
#
#L<$homepage>
#
#  git clone $repository
#
SUPPORT_SECTION

    # remove the protective '#'
    $section =~ s{ ^ [#] }{}xsmg;

    if (
        $content !~ s{
            [\s\n]*
            ^ =head1 \s+ SUPPORT [^\n]* $
            .*?
            ^ (?= = (?: head1 | cut ) )
        }{$section}xsm
      )
    {
        $self->log_fatal("Unable to replace SUPPORT section in file $filename.");
    }

    $file->content($content);

    return;
}

sub _update_pod_section_version {
    my ( $self, $file ) = @_;

    my $filename = $file->name;
    my $content  = $file->content;

    my $section = "\n\n=head1 VERSION\n\nVersion " . $self->zilla->version . "\n\n";

    if (
        $content !~ s{
            [\s\n]*
            ^ =head1 \s+ VERSION [^\n]* $
            .*?
            ^ (?= = (?: head1 | cut ) )
        }{$section}xsm
      )
    {
        $self->log_fatal("Unable to replace VERSION section in file $filename.");
    }

    $file->content($content);

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::UpdatePod - update Pod with project specific defaults

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

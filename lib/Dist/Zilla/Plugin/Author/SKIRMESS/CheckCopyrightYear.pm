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

package Dist::Zilla::Plugin::Author::SKIRMESS::CheckCopyrightYear;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::BeforeBuild);

use namespace::autoclean;

has whitelisted_licenses => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [qw(Software::License::FreeBSD Local::Software::License::ISC)] },
);

sub before_build {
    my ($self) = @_;

    my $zilla   = $self->zilla;
    my $license = $zilla->license;

    my %whitelisted_license = map { $_ => 1 } @{ $self->whitelisted_licenses };

    my $license_package = ref $license;
    $self->log_fatal("License '$license_package' is not whitelisted") if !exists $whitelisted_license{$license_package};

    my $this_year = (localtime)[5] + 1900;
    my $year      = $license->year;
    if ( $year =~ m{ ^ [0-9]{4} $ }xsm ) {
        $self->log_fatal("Copyright year is '$year' but this year is '$this_year'. The correct copyright year is '$year-$this_year'") if $year ne $this_year;
        return;
    }

    $self->log_fatal("Copyright year must either be '$this_year' or 'yyyy-$this_year' but is '$year'") if $year !~ m{ ^ ( [0-9]{4} ) - ( [0-9]{4} ) $ }xsm;
    my $first_year = $1;    ## no critic (RegularExpressions::ProhibitCaptureWithoutTest)
    my $last_year  = $2;    ## no critic (RegularExpressions::ProhibitCaptureWithoutTest)

    $self->log_fatal("First year in copyright year must be a smaller number then second but is '$year'") if $first_year >= $last_year;

    $self->log_fatal("Copyright year is '$year' but this year is '$this_year'. The correct copyright year is '$first_year-$this_year'") if $last_year ne $this_year;

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CheckCopyrightYear - check that the copyright year is correct

=head1 VERSION

Version 1.000

=head1 SYNOPSIS

In your F<dist.ini>:

[Author::SKIRMESS::CheckCopyrightYear]

=head1 DESCRIPTION

This plugin runs before the build and checks that the license is one of our whitelisted licenses and that the copyright year makes sense.

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

=cut

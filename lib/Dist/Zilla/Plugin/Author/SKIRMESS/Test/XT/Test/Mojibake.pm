package Dist::Zilla::Plugin::Author::SKIRMESS::Test::XT::Test::Mojibake;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.005';

use Moose;

has 'filename' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'xt/author/mojibake.t',
);

with qw(
  Dist::Zilla::Role::Author::SKIRMESS::Test::XT
);

use namespace::autoclean;

sub test_body {
    my ($self) = @_;

    return <<'TEST_BODY';
use Test::Mojibake;

all_files_encoding_ok( grep { -d } qw( bin lib t xt ) );
TEST_BODY
}

1;

# vim: ts=4 sts=4 sw=4 et: syntax=perl

package Dist::Zilla::Plugin::Author::SKIRMESS::MetaJSON::RemoveDevelopPrereqs;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::FileMunger);

use JSON::MaybeXS qw();
use Scalar::Util qw(blessed);

use namespace::autoclean;

has filename => (
    is      => 'ro',
    isa     => 'Str',
    default => 'META.json',
);

sub munge_file {
    my ( $self, $file ) = @_;

    return if $file->name ne $self->filename;

    $self->log_fatal( q{'} . $file->name . q{' is not a 'Dist::Zilla::File::FromCode'} ) if blessed($file) ne 'Dist::Zilla::File::FromCode';

    my $orig_coderef = $file->code();
    $file->code(
        sub {
            $self->log_debug( [ 'Removing develop prereqs from %s', $file->name ] );

            my $json = JSON::MaybeXS->new( canonical => 1, pretty => 1, ascii => 1 );

            my $meta_json = $json->decode( $file->$orig_coderef() );
            delete $meta_json->{prereqs}->{develop};

            my $content = $json->encode($meta_json) . "\n";
            return $content;
        },
    );

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::MetaJSON::RemoveDevelopPrereqs - Remove develop prereqs from META.json file

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

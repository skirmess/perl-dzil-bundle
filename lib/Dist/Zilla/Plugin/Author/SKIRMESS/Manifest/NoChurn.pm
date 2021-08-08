package Dist::Zilla::Plugin::Author::SKIRMESS::Manifest::NoChurn;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

extends 'Dist::Zilla::Plugin::Manifest';

use Scalar::Util qw(blessed);

use namespace::autoclean;

override add_file => sub {
    my ( $self, $file ) = @_;

    my $name = $file->name;
    $self->log_fatal("'$name' is not a 'Dist::Zilla::File::FromCode'") if blessed($file) ne 'Dist::Zilla::File::FromCode';
    $self->log_fatal("File '$name' is not called 'MANIFEST'")          if $name ne 'MANIFEST';
    $self->log_fatal("File '$name' is of type 'bytes'")                if !$file->is_bytes;

    my $orig_coderef = $file->code();

    $file->code(
        sub {
            $self->log_debug( [ 'Removing churn from %s', $file->name ] );
            my $content = join "\n", grep { $_ !~ m{ ^ [#] }xsm } split /\n/, $file->$orig_coderef;    ## no critic (RegularExpressions::ProhibitUselessTopic, RegularExpressions::RequireDotMatchAnything, RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching)
            return "$content\n";
        },
    );

    super();

    return;
};

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::Manifest::NoChurn - Remove churn from MANIFEST file

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

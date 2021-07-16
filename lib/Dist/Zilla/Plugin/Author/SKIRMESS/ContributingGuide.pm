package Dist::Zilla::Plugin::Author::SKIRMESS::ContributingGuide;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(
  Dist::Zilla::Role::Author::SKIRMESS::Resources
  Dist::Zilla::Role::FileGatherer
  Dist::Zilla::Role::TextTemplate
  Dist::Zilla::Role::FileMunger
);

use Dist::Zilla::File::InMemory;

use namespace::autoclean;

has _filename => (
    is      => 'ro',
    isa     => 'Str',
    default => 'CONTRIBUTING',
);

sub gather_files {
    my ($self) = @_;

    my $file = Dist::Zilla::File::InMemory->new(
        {
            name    => $self->_filename,
            content => $self->_contributing,
        },
    );

    $self->add_file($file);

    return;
}

sub munge_file {
    my ( $self, $file ) = @_;

    return if $file->name ne $self->_filename;

    ( my $main_module = $self->zilla->name ) =~ s{-}{::}xsmg;

    $file->content(
        $self->fill_in_string(
            $file->content,
            {
                self        => \$self,
                main_module => $main_module,
            },
        ),
    );

    return;
}

sub _contributing {
    my ($self) = @_;

    my $content = <<'CONTRIBUTING_FILE';

CONTRIBUTING

Thank you for considering contributing to this distribution. This file
contains instructions that will help you work with the source code. If you
have any questions or difficulties, you can reach the maintainer(s) by email
or through the bug queue described later in this document.

The distribution, which can be found on CPAN, contains only the files useful
to a user of the distribution.

The project contains the same files as the distribution but additionally
includes author tests and various configuration files used to develop or
release the distribution.

You do not need the project to contribute patches. The project is only used
to create a tarball and release it or if you would like to run the author
tests.


WORKING WITH THE DISTRIBUTION

You can run tests directly using the prove tool:

  $ prove -l
  $ prove -lv t/some_test_file.t
  $ prove -lvr t/

or with the Makefile:

  $ export AUTOMATED_TESTING=1
  $ perl Makefile.PL
  $ make
  $ make test

prove is entirely sufficent for you to test any patches you have.

You may need to satisfy some dependencies. If you use cpanminus, you can do
it without downloading the tarball first:

  $ cpanm --reinstall --installdeps {{ $main_module }}


WORKING WITH THE PROJECT

The project can be found on GitHub:
{{ $self->homepage }}

The project is managed with Dist::Zilla. You do not need Dist::Zilla to
contribute patches or run the author tests. You do need Dist::Zilla to create
a tarball.

If you would like to work with the project, clone it with the following
commands:

  $ git clone {{ $self->repository }}

You may need to satisfy some dependencies. You can use cpanminus in the
cloned project to install them:

  $ cpanm --installdeps --with-develop .

Or if you plan on using Dist::Zilla, install all author dependencies with:

  $ cpanm --installdeps --with-develop --with-feature dzil .

You can run tests directly using the prove tool:

  $ prove -l
  $ prove -lv t/some_test_file.t
  $ prove -lvr t/

Including the author tests:

  $ prove -lvr xt/

or with Dist::Zilla:

  $ dzil test
  $ dzil test --release


SUBMITTING PATCHES

The code for this distribution is hosted at GitHub. The repository is:
{{ $self->homepage }}
You can submit code changes by forking the repository, pushing your code
changes to your clone, and then submitting a pull request. Detailed
instructions for doing that is available here:
https://help.github.com/articles/creating-a-pull-request

If you have found a bug, but do not have an accompanying patch to fix it, you
can submit an issue report here:
{{ $self->bugtracker }}

If you send me a patch or pull request, your name and email address will be
included as a contributor (using the attribution on the commit or patch),
unless you specifically request for it not to be. If you wish to be listed
under a different name or address, you should submit a pull request to the
.mailmap file to contain the correct mapping.

Alternatively you can also submit a patch by email to the maintainer(s).
There is no need for you to use Git or GitHub.
CONTRIBUTING_FILE

    return $content;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::ContributingGuide - build an CONTRIBUTING file

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

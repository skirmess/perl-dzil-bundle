package Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Merge;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::AfterBuild);

use Module::CPANfile 1.1004 ();
use Path::Tiny qw(path);

use namespace::autoclean;

has feature => (
    is  => 'ro',
    isa => 'Str',
);

has feature_description => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub { $_[0]->feature },
);

has filename => (
    is      => 'ro',
    isa     => 'Str',
    default => 'cpanfile',
);

has source => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

sub after_build {
    my ($self) = @_;

    my $zilla = $self->zilla;

    my $src_file = path( $self->source )->absolute( $zilla->root );
    $self->log_fatal("cpanfile '$src_file' does not exist") if !-f $src_file;

    # Features in the source cpanfile are ignored because we only look at the
    # prereqs.
    my $src_obj = Module::CPANfile->load( $src_file->stringify );

    my $cpanfile = path( $zilla->root )->child( $self->filename );
    $self->log_fatal("cpanfile '$cpanfile' does not exist") if !-f $cpanfile;

    my $cpanfile_obj     = Module::CPANfile->load($cpanfile);
    my $cpanfile_prereqs = $cpanfile_obj->prereqs;
    my $cpanfile_str     = q{};

    my $feature_identifier = $self->feature;
    my $feature_description;
    if ( defined $feature_identifier ) {

        # Merge cpanfile into a feature
        $feature_description = $self->feature_description;
    }
    else {
        # Merge cpanfile into base prereqs
        $cpanfile_prereqs = $cpanfile_prereqs->with_merged_prereqs( $src_obj->prereqs );
    }

  FEATURE:
    for my $feature ( $cpanfile_obj->features ) {
        my $prereqs     = $feature->prereqs;
        my $identifier  = $feature->identifier;
        my $description = $feature->description;

        if ( defined $feature_identifier && $identifier eq $feature_identifier ) {
            $prereqs     = $prereqs->with_merged_prereqs( $src_obj->prereqs );
            $identifier  = $feature_identifier;
            $description = $feature_description;
        }

        $cpanfile_str .= "feature '$identifier', '$description' => sub {\n";
        $cpanfile_str .= Module::CPANfile->from_prereqs( $prereqs->as_string_hash )->to_string;
        $cpanfile_str .= "};\n";

    }

    $cpanfile_str .= Module::CPANfile->from_prereqs( $cpanfile_prereqs->as_string_hash )->to_string;
    $cpanfile->spew($cpanfile_str);

    Module::CPANfile->load( $cpanfile->stringify )->save( $cpanfile->stringify );

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Merge - merge a cpanfile into the cpanfile in the project

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

package Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Sanitize;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::AfterBuild);

use CPAN::Meta::Prereqs::Filter qw(filter_prereqs);
use Module::CPANfile 1.1004 ();
use Path::Tiny qw(path);

use namespace::autoclean;

has filename => (
    is      => 'ro',
    isa     => 'Str',
    default => 'cpanfile',
);

sub after_build {
    my ($self) = @_;

    my $zilla = $self->zilla;

    my $cpanfile = path( $zilla->root )->child( $self->filename );
    $self->log_fatal("cpanfile '$cpanfile' does not exist") if !-f $cpanfile;

    # load cpanfile
    my $cpanfile_obj = Module::CPANfile->load($cpanfile);

    # sanitize the base prereqs (should be mostly a no-op)
    my $prereqs = filter_prereqs( $cpanfile_obj->prereqs, sanitize => 1 );

    # rewrite the cpanfile with only the base prereqs
    Module::CPANfile->from_prereqs( $prereqs->as_string_hash )->save($cpanfile);

    # "sanitize" all features
    for my $feature ( $cpanfile_obj->features ) {
        my $identifier  = $feature->identifier;
        my $description = $feature->description;

        # merge the feature prereqs with the base prereqs
        my $merged_prereqs = $prereqs->with_merged_prereqs( $feature->prereqs );

        # sanitize the merged prereqs
        my $merged_filtered_prereqs = filter_prereqs( $merged_prereqs, sanitize => 1 );

        # Remove all prereqs from the merged prereqs that are also in the
        # base prereqs. This leaves us with the diff between the merged
        # prereqs and the base prereqs which is basically what must be in the
        # feature.
        for my $phase ( $merged_filtered_prereqs->phases ) {
            for my $type ( $merged_filtered_prereqs->types_in($phase) ) {
                my $req_feature = $merged_filtered_prereqs->requirements_for( $phase, $type );
                my $req_prereqs = $prereqs->requirements_for( $phase, $type );

              MODULE:
                for my $module ( $req_feature->required_modules ) {
                    my $req_mod_prereqs = $req_prereqs->requirements_for_module($module);
                    next MODULE if !defined $req_mod_prereqs;

                    my $req_mod_feature = $req_feature->requirements_for_module($module);
                    next MODULE if $req_mod_prereqs ne $req_mod_feature;

                    $self->log_debug("Removing module $module from $phase/$type");
                    $req_feature->clear_requirement($module);
                }
            }
        }

        # append the sanitized feature to the new cpanfile
        $cpanfile->append("feature '$identifier', '$description' => sub {\n");
        $cpanfile->append( Module::CPANfile->from_prereqs( $merged_filtered_prereqs->as_string_hash )->to_string );
        $cpanfile->append("};\n");
    }

    # rewrite the new cpanfile to "pretty print" it
    Module::CPANfile->load( $cpanfile->stringify )->save( $cpanfile->stringify );

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Sanitize - Remove double-declared entries from the cpanfile in the project

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

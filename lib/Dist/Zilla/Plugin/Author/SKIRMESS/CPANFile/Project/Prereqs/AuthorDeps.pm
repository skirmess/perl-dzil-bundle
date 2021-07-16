package Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Prereqs::AuthorDeps;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

with qw(Dist::Zilla::Role::AfterBuild);

use Dist::Zilla::Util                    ();
use Dist::Zilla::Util::BundleInfo        ();
use Dist::Zilla::Util::ExpandINI::Reader ();
use List::Util qw(pairs);
use Module::CPANfile 1.1004 ();
use Path::Tiny qw(path);

use namespace::autoclean;

sub mvp_multivalue_args {
    return (
        qw(
          expand_bundle
          skip
        )
    );
}

has expand_bundle => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub { [] },
);

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

has skip => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub { [] },
);

sub after_build {
    my ($self) = @_;

    my $zilla    = $self->zilla;
    my $dist_ini = path( $zilla->root )->child('dist.ini');

    $self->log_fatal("File '$dist_ini' does not exist") if !-f $dist_ini;

    my %bundle_to_expand;
    @bundle_to_expand{ @{ $self->expand_bundle } } = ();

    my %skip;
    @skip{ @{ $self->skip } } = ();

    my $dependencies = q{};
    my $reader       = Dist::Zilla::Util::ExpandINI::Reader->new();

  SECTION:
    for my $section ( @{ $reader->read_file("$dist_ini") } ) {
        my $version = $self->_get_version_from_section( $section->{lines} );

        if ( $section->{name} eq '_' ) {

            # Add Dist::Zilla
            $dependencies .= $self->_create_plugin_cpanfile_entry_string( 'Dist::Zilla', $version );
            next SECTION;
        }

        my $package_name = Dist::Zilla::Util->expand_config_package_name( $section->{package} );
        next SECTION if exists $skip{$package_name};

        if ( $section->{package} !~ m{ ^ [@] }msx ) {

            # Add plugin
            $dependencies .= $self->_create_plugin_cpanfile_entry_string( $package_name, $version );
            next SECTION;
        }

        if ( !exists $bundle_to_expand{$package_name} ) {

            # Add Bundle
            $dependencies .= $self->_create_plugin_cpanfile_entry_string( $package_name, $version );
            next SECTION;
        }

        # Add expanded bundle

        # Bundles inside the bundle are expanded automatically, because
        # BundleInfo loads the bundle through the official API.
        my $bundle = Dist::Zilla::Util::BundleInfo->new(
            bundle_name    => $section->{package},
            bundle_payload => $section->{lines},
        );

      PLUGIN:
        for my $plugin ( $bundle->plugins ) {
            $package_name = $plugin->module;
            next PLUGIN if exists $skip{$package_name};

            # payload_list calls _autoexpand_list which is broken and fails
            # if a value is a code ref, we have to create the list ourself
            my $payload = $plugin->payload;
            my @payload_list;
          KEY:
            for my $key ( sort keys %{$payload} ) {
                my $value = $payload->{$key};
                if ( ref $value eq ref sub { } ) {
                    push @payload_list, $key, $value;
                }
                else {
                    push @payload_list, $plugin->_autoexpand_list( $key, $value );
                }
            }

            $version = $self->_get_version_from_section( \@payload_list );
            $dependencies .= $self->_create_plugin_cpanfile_entry_string( $package_name, $version );
        }
    }

    my $feature = $self->feature;

    # Add dependencies to existing cpanfile
    my $cpanfile = path( $zilla->root )->child( $self->filename );
    $cpanfile->append("on develop => sub {\n");
    if ( defined $feature ) {
        my $feature_description = $self->feature_description;
        $cpanfile->append("feature '$feature', '$feature_description' => sub {\n");
    }
    $cpanfile->append($dependencies);
    $cpanfile->append("};\n");
    if ( defined $feature ) {
        $cpanfile->append("};\n");
    }

    # Reformat cpanfile
    Module::CPANfile->load($cpanfile)->save($cpanfile);

    return;
}

sub _create_plugin_cpanfile_entry_string {
    my ( $self, $package, $version ) = @_;

    my $line = "requires '$package'";
    if ($version) {
        $line .= ", $version";
    }
    $line .= ";\n";

    return $line;
}

sub _get_version_from_section {
    my ( $self, $lines_ref ) = @_;

    my $version = 0;

  LINE:
    for my $line_ref ( pairs @{$lines_ref} ) {
        my ( $key, $value ) = @{$line_ref};
        next LINE unless $key eq ':version';
        $version = $value;
    }

    return $version;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Prereqs::AuthorDeps - Add Dist::Zilla authordeps prereqs as develop dependencies with feature dzil to the cpanfile in the project

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

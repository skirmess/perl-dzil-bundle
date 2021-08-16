package Dist::Zilla::Plugin::Author::SKIRMESS::MakeMaker::Awesome;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';

with 'Dist::Zilla::Role::PPI';

has _has_extended_prereqs => (
    is      => 'rw',
    default => 0,
);

use CPAN::Meta::Requirements;
use Data::Dumper;
use JSON::PP;
use Perl::PrereqScanner 1.016;
use Perl::Tidy;
use Term::ANSIColor qw(colored);

use namespace::autoclean;

override build => sub {
    my ($self) = @_;

    # Needed to run tests under xt/smoke with 'dzil test'
    $self->log('Setting EXTENDED_TESTING=1');
    local $ENV{EXTENDED_TESTING} = 1;

    super();
};

override _build_MakeFile_PL_template => sub {
    my ($self) = @_;

    # Template copied from Dist::Zilla::Plugin::MakeMaker::Awesome and
    # adjusted
    return <<'TEMPLATE';
{{ $perl_prereq ? qq[use $perl_prereq;] : ''; }}
use strict;
use warnings;

use ExtUtils::MakeMaker{{
    0+$eumm_version
        ? ' ' . (0+$eumm_version eq $eumm_version ? $eumm_version : "'" . $eumm_version . "'")
        : '' }};

{{ $header }}

{{ $share_dir_block[0] }}

my {{ $WriteMakefileArgs }}
{{
    @$extra_args ? "%WriteMakefileArgs = (\n"
        . join('', map "    $_,\n", '%WriteMakefileArgs', @$extra_args)
        . ");\n"
    : '';
}}
my {{ $fallback_prereqs }}

{{ $add_smoker_test_requirements }}

if ( !eval { ExtUtils::MakeMaker->VERSION('6.63_03') } ) {
    delete $WriteMakefileArgs{TEST_REQUIRES};
    delete $WriteMakefileArgs{BUILD_REQUIRES};
    $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

if ( !eval { ExtUtils::MakeMaker->VERSION(6.52) } ) {
    delete $WriteMakefileArgs{CONFIGURE_REQUIRES};
}

WriteMakefile(%WriteMakefileArgs);

{{ $share_dir_block[1] }}

{{ $footer }}
# vim: ts=4 sts=4 sw=4 et: syntax=perl
TEMPLATE
};

override _dump_as => sub {
    my ( $self, $ref, $name ) = @_;

    my $dumper = Data::Dumper->new( [$ref], [$name] );
    $dumper->Sortkeys(1);
    $dumper->Indent(1);
    $dumper->Useqq(0);
    $dumper->Quotekeys(0);
    $dumper->Trailingcomma(1);

    my $dumped = $dumper->Dump;

    # Useqq(1) does not quote 0 but double quote the keys
    # Useqq(0) does not double quote keys but quote 0
    $dumped =~ s{ ( => \s+ ) '0' }{${1}0}xsmg;

    return $dumped;
};

override fill_in_string => sub {
    my ( $self, $content, $data_ref ) = @_;

    if ( $self->_has_extended_prereqs ) {
        $data_ref->{add_smoker_test_requirements} = <<'EOF';
if ( $ENV{AUTOMATED_TESTING} || $ENV{EXTENDED_TESTING} ) {
    $WriteMakefileArgs{test}{TESTS} .= ' xt/smoke/*.t';
    _add_smoker_test_requirements();
}
EOF
    }

    return $self->SUPER::fill_in_string( $content, $data_ref );
};

override setup_installer => sub {
    my ($self) = @_;

    my $meta_req  = CPAN::Meta::Requirements->new;
    my $smoke_req = CPAN::Meta::Requirements->new;

    my $meta_seen  = 0;
    my $smoke_seen = 0;
    my $makefile_pl;

  FILE:
    for my $file ( @{ $self->zilla->files } ) {
        if ( $file->name eq 'Makefile.PL' ) {
            $makefile_pl = $file;
            next FILE;
        }

        if ( $file->name eq 'META.json' ) {

            $self->log_fatal('META.json seen twice - internal error') if $meta_seen;
            $meta_seen = 1;

            my $prereqs = decode_json( $file->content )->{prereqs};

          PHASE:
            for my $phase (qw(runtime test)) {
                next PHASE if !exists $prereqs->{$phase}{requires};

                for my $module ( keys %{ $prereqs->{$phase}{requires} } ) {
                    $meta_req->add_minimum( $module, $prereqs->{$phase}{requires}{$module} );
                }
            }

            next FILE;
        }

        next FILE if $file->name !~ m{ ^ xt/smoke/ }xsm;

        $smoke_req->add_requirements( Perl::PrereqScanner->new->scan_ppi_document( $self->ppi_document_for_file($file) ) );
        $smoke_seen++;
    }

    $self->log_fatal('META.json not seen')   if !$meta_seen;
    $self->log_fatal('Makefile.PL not seen') if !defined $makefile_pl;

    if ($smoke_seen) {
        $self->_has_extended_prereqs(1);

        # Merge the requirements from META.json into the requirements from the
        # smoke tests
        $smoke_req->add_requirements($meta_req);

        # Remove the requirements that are the same from the smoke_req - the
        # other are guaranteed to be bigger or additional ones
        my $meta_hash  = $meta_req->as_string_hash;
        my $smoke_hash = $smoke_req->as_string_hash;

      MODULE:
        for my $module ( keys %{$meta_hash} ) {
            $self->log_fatal('This should never happen') if !exists $smoke_hash->{$module};

            if ( $smoke_hash->{$module} eq $meta_hash->{$module} ) {
                delete $smoke_hash->{$module};
            }
        }

        push @{ $self->footer_strs }, split /\n/, <<'EOF';    ## no critic (RegularExpressions::RequireDotMatchAnything, RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching)
sub test_requires {
    my ( $module, $version_or_range ) = @_;
    $WriteMakefileArgs{TEST_REQUIRES}{$module} = $FallbackPrereqs{$module} = $version_or_range;
    return;
}

sub _add_smoker_test_requirements {
EOF

        for my $module ( sort keys %{$smoke_hash} ) {
            push @{ $self->footer_strs }, qq{    test_requires('$module', } . ( $smoke_hash->{$module} eq '0' ? 0 : qq{'$smoke_hash->{$module}'} ) . ');';
        }

        push @{ $self->footer_strs }, '    return;', '}';

    }

    super();

    my $source_string = $makefile_pl->content;
    my $dest_string;
    my $stderr_string;
    my $errorfile_string;

    local @ARGV;    ## no critic (Variables::RequireInitializationForLocalVars)
    my $tidy_error = Perl::Tidy::perltidy(
        source      => \$source_string,
        destination => \$dest_string,
        stderr      => \$stderr_string,
        errorfile   => \$errorfile_string,
    );

    if ($stderr_string) {
        $self->log( colored( $stderr_string, 'yellow' ) );
        $tidy_error = 1;
    }

    if ($errorfile_string) {
        $self->log( colored( $errorfile_string, 'yellow' ) );
        $tidy_error = 1;
    }

    $self->log_fatal( colored( 'Exiting because of serious errors', 'red' ) ) if $tidy_error;

    $makefile_pl->content($dest_string);

    return;
};

override test => sub {
    my ($self) = @_;

    # Needed to run tests under xt/smoke with 'dzil test'
    $self->log('Setting EXTENDED_TESTING=1');
    local $ENV{EXTENDED_TESTING} = 1;

    super();
};

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::Author::SKIRMESS::MakeMaker::Awesome - a more awesome MakeMaker plugin for Dist::Zilla

=head1 VERSION

Version 1.000

=head1 SYNOPSIS

In your F<dist.ini>:

[Author::SKIRMESS::MakeMaker::Awesome]

=head1 DESCRIPTION

This plugin creates the Makefile.PL file.

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

package Dist::Zilla::Plugin::Author::SKIRMESS::MakeMaker::Awesome;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.000';

use Moose;

extends 'Dist::Zilla::Plugin::MakeMaker::Awesome';

with 'Dist::Zilla::Role::PPI';

use CPAN::Meta::Requirements;
use JSON::PP;
use Perl::PrereqScanner 1.016;

use namespace::autoclean;

override build => sub {
    my ($self) = @_;

    # Needed to run tests under xt/smoke with 'dzil test'
    $self->log('Setting AUTOMATED_TESTING=1');
    local $ENV{AUTOMATED_TESTING} = 1;

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
IS_SMOKER_BLOCK
unless ( eval { ExtUtils::MakeMaker->VERSION('6.63_03') } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);

{{ $share_dir_block[1] }}

{{ $footer }}
TEMPLATE
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

    if ( !$smoke_seen ) {
        my $content = $makefile_pl->content;
        $content =~ s{IS_SMOKER_BLOCK}{}xsm;
        $makefile_pl->content($content);
    }
    else {
        my $is_smoker_text = <<'EOF';
if (is_smoker()) {
  $WriteMakefileArgs{test}{TESTS} .= " xt/smoke/*.t";
  _add_smoker_test_requirements();
}
EOF
        my $content = $makefile_pl->content;
        $content =~ s{IS_SMOKER_BLOCK}{$is_smoker_text}xsm;
        $makefile_pl->content($content);

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

        # copied from Dist::Zilla::Plugin::DynamicPrereqs 0.039 and slightly
        # adjusted
        push @{ $self->footer_strs }, split /\n/, <<'EOF';    ## no critic (RegularExpressions::RequireDotMatchAnything, RegularExpressions::RequireExtendedFormatting, RegularExpressions::RequireLineBoundaryMatching)
sub _add_prereq {
  my ($mm_key, $module, $version_or_range) = @_;
  $version_or_range ||= 0;
  warn "$module already exists in $mm_key (at version $WriteMakefileArgs{$mm_key}{$module}) -- need to do a sane metamerge!"
    if exists $WriteMakefileArgs{$mm_key}{$module}
      and $WriteMakefileArgs{$mm_key}{$module} ne '0'
      and $WriteMakefileArgs{$mm_key}{$module} ne $version_or_range;
  warn "$module already exists in FallbackPrereqs (at version $FallbackPrereqs{$module}) -- need to do a sane metamerge!"
    if exists $FallbackPrereqs{$module} and $FallbackPrereqs{$module} ne '0'
        and $FallbackPrereqs{$module} ne $version_or_range;
  $WriteMakefileArgs{$mm_key}{$module} = $FallbackPrereqs{$module} = $version_or_range;
  return;
}

sub is_smoker {
  return $ENV{AUTOMATED_TESTING} ? 1 : 0;
}

sub test_requires {
  my ($module, $version_or_range) = @_;
  _add_prereq(TEST_REQUIRES => $module, $version_or_range);
}

sub _add_smoker_test_requirements {
EOF

        for my $module ( sort keys %{$smoke_hash} ) {
            push @{ $self->footer_strs }, qq{  test_requires('$module', } . ( $smoke_hash->{$module} eq '0' ? 0 : qq{'$smoke_hash->{$module}'} ) . ');';
        }

        push @{ $self->footer_strs }, '}';

    }

    return super();
};

override test => sub {
    my ($self) = @_;

    # Needed to run tests under xt/smoke with 'dzil test'
    $self->log('Setting AUTOMATED_TESTING=1');
    local $ENV{AUTOMATED_TESTING} = 1;

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

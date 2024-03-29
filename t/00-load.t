#!perl

# vim: ts=4 sts=4 sw=4 et: syntax=perl
#
# Copyright (c) 2017-2023 Sven Kirmess
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

# Automatically generated file; DO NOT EDIT.

use Test::More 0.88;

use lib qw(lib);

my @modules = qw(
  Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Sanitize
  Dist::Zilla::Plugin::Author::SKIRMESS::CheckCopyrightYear
  Dist::Zilla::Plugin::Author::SKIRMESS::CheckFilesInDistribution
  Dist::Zilla::Plugin::Author::SKIRMESS::ContributingGuide
  Dist::Zilla::Plugin::Author::SKIRMESS::CopyAllFilesFromDistributionToProject
  Dist::Zilla::Plugin::Author::SKIRMESS::MakeMaker::Awesome
  Dist::Zilla::Plugin::Author::SKIRMESS::MinimumPerl
  Dist::Zilla::Plugin::Author::SKIRMESS::PromptIfStale::CPANFile::Project
  Dist::Zilla::Plugin::Author::SKIRMESS::RunExtraTests::FromProject
  Dist::Zilla::Plugin::Author::SKIRMESS::Test::Load
  Dist::Zilla::Plugin::Author::SKIRMESS::UpdatePod
  Dist::Zilla::PluginBundle::Author::SKIRMESS
  Dist::Zilla::Role::Author::SKIRMESS::Resources
  Local::Software::License::ISC
);

plan tests => scalar @modules;

for my $module (@modules) {
    require_ok($module) or BAIL_OUT();
}

#!perl

use 5.006;
use strict;
use warnings;

# Automatically generated file; DO NOT EDIT.

use Test::More 0.88;

use lib qw(lib);

my @modules = qw(
  Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project
  Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Merge
  Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Prereqs::AuthorDeps
  Dist::Zilla::Plugin::Author::SKIRMESS::CPANFile::Project::Sanitize
  Dist::Zilla::Plugin::Author::SKIRMESS::CheckCopyrightYear
  Dist::Zilla::Plugin::Author::SKIRMESS::CheckFilesInDistribution
  Dist::Zilla::Plugin::Author::SKIRMESS::ContributingGuide
  Dist::Zilla::Plugin::Author::SKIRMESS::CopyAllFilesFromDistributionToProject
  Dist::Zilla::Plugin::Author::SKIRMESS::MetaJSON::RemoveDevelopPrereqs
  Dist::Zilla::Plugin::Author::SKIRMESS::MinimumPerl
  Dist::Zilla::Plugin::Author::SKIRMESS::PromptIfStale::CPANFile::Project
  Dist::Zilla::Plugin::Author::SKIRMESS::RemoveWhitespaceFromEndOfLine
  Dist::Zilla::Plugin::Author::SKIRMESS::RunExtraTests::FromProject
  Dist::Zilla::Plugin::Author::SKIRMESS::Test::Load
  Dist::Zilla::Plugin::Author::SKIRMESS::UpdatePod
  Dist::Zilla::PluginBundle::Author::SKIRMESS
  Dist::Zilla::Role::Author::SKIRMESS::Resources
);

plan tests => scalar @modules;

for my $module (@modules) {
    require_ok($module) || BAIL_OUT();
}

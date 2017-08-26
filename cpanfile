requires "Carp" => "0";
requires "Dist::Zilla" => "0";
requires "Dist::Zilla::Plugin::Authority" => "1.009";
requires "Dist::Zilla::Plugin::AutoPrereqs" => "0";
requires "Dist::Zilla::Plugin::Bootstrap::lib" => "0";
requires "Dist::Zilla::Plugin::CPANFile" => "0";
requires "Dist::Zilla::Plugin::CheckChangesHasContent" => "0";
requires "Dist::Zilla::Plugin::CheckIssues" => "0";
requires "Dist::Zilla::Plugin::CheckMetaResources" => "0";
requires "Dist::Zilla::Plugin::CheckPrereqsIndexed" => "0";
requires "Dist::Zilla::Plugin::CheckSelfDependency" => "0";
requires "Dist::Zilla::Plugin::CheckStrictVersion" => "0";
requires "Dist::Zilla::Plugin::ConfirmRelease" => "0";
requires "Dist::Zilla::Plugin::CopyFilesFromBuild" => "0";
requires "Dist::Zilla::Plugin::CopyFilesFromRelease" => "0";
requires "Dist::Zilla::Plugin::CopyrightYearFromGit" => "0";
requires "Dist::Zilla::Plugin::ExecDir" => "0";
requires "Dist::Zilla::Plugin::Git::Check" => "0";
requires "Dist::Zilla::Plugin::Git::CheckFor::CorrectBranch" => "0";
requires "Dist::Zilla::Plugin::Git::CheckFor::MergeConflicts" => "0";
requires "Dist::Zilla::Plugin::Git::Commit" => "0";
requires "Dist::Zilla::Plugin::Git::Contributors" => "0";
requires "Dist::Zilla::Plugin::Git::GatherDir" => "2.016";
requires "Dist::Zilla::Plugin::Git::Push" => "0";
requires "Dist::Zilla::Plugin::Git::Remote::Check" => "0";
requires "Dist::Zilla::Plugin::Git::Tag" => "0";
requires "Dist::Zilla::Plugin::GithubMeta" => "0";
requires "Dist::Zilla::Plugin::InstallGuide" => "1.200007";
requires "Dist::Zilla::Plugin::License" => "0";
requires "Dist::Zilla::Plugin::MakeMaker" => "0";
requires "Dist::Zilla::Plugin::Manifest" => "0";
requires "Dist::Zilla::Plugin::ManifestSkip" => "0";
requires "Dist::Zilla::Plugin::MetaConfig" => "0";
requires "Dist::Zilla::Plugin::MetaJSON" => "0";
requires "Dist::Zilla::Plugin::MetaNoIndex" => "0";
requires "Dist::Zilla::Plugin::MetaProvides::Package" => "0";
requires "Dist::Zilla::Plugin::MetaYAML" => "0";
requires "Dist::Zilla::Plugin::MinimumPerl" => "1.006";
requires "Dist::Zilla::Plugin::NextRelease" => "0";
requires "Dist::Zilla::Plugin::Prereqs::Plugins" => "0";
requires "Dist::Zilla::Plugin::PromptIfStale" => "0";
requires "Dist::Zilla::Plugin::PruneCruft" => "0";
requires "Dist::Zilla::Plugin::ReadmeAnyFromPod" => "0";
requires "Dist::Zilla::Plugin::RemovePrereqs::Provided" => "0";
requires "Dist::Zilla::Plugin::ReversionOnRelease" => "0";
requires "Dist::Zilla::Plugin::RunExtraTests" => "0";
requires "Dist::Zilla::Plugin::ShareDir" => "0";
requires "Dist::Zilla::Plugin::TestRelease" => "0";
requires "Dist::Zilla::Plugin::UploadToCPAN" => "0";
requires "Dist::Zilla::Plugin::VerifyPhases" => "0";
requires "Dist::Zilla::Plugin::VersionFromMainModule" => "0";
requires "Dist::Zilla::Role::BeforeBuild" => "0";
requires "Dist::Zilla::Role::Plugin" => "0";
requires "Dist::Zilla::Role::PluginBundle::Easy" => "0";
requires "List::MoreUtils" => "0";
requires "Moose" => "0.99";
requires "Moose::Role" => "0";
requires "Path::Tiny" => "0";
requires "namespace::autoclean" => "0.09";
requires "perl" => "5.006";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "Test::More" => "0";
  requires "perl" => "5.006";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "perl" => "5.006";
};

on 'develop' => sub {
  requires "File::Spec" => "0";
  requires "Perl::Critic::Utils" => "0";
  requires "Pod::Wordlist" => "0";
  requires "Test::CPAN::Meta" => "0.12";
  requires "Test::CPAN::Meta::JSON" => "0";
  requires "Test::DistManifest" => "1.003";
  requires "Test::Kwalitee" => "0";
  requires "Test::MinimumVersion" => "0.008";
  requires "Test::Mojibake" => "0";
  requires "Test::More" => "0.88";
  requires "Test::NoTabs" => "0";
  requires "Test::Perl::Critic" => "0";
  requires "Test::Pod" => "1.26";
  requires "Test::Pod::No404s" => "0";
  requires "Test::Portability::Files" => "0";
  requires "Test::Spelling" => "0.12";
  requires "Test::Version" => "0.04";
};

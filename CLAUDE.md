# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A private [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) plugin bundle
(`Dist::Zilla::PluginBundle::Author::SKIRMESS`) plus the custom plugins it needs.
It is **not released to CPAN**; consuming projects pull it in via the
`Git::Checkout` plugin (see the SYNOPSIS in the main module) and load it with
`[lib] lib = dzil-bundle/lib`.

The bundle also builds *itself*. `lib/.../PluginBundle/Author/SKIRMESS.pm` has a
`_self_build` attribute (true when cwd equals the bundle checkout); several
plugins are configured differently or skipped in that case. Any change to the
bundle must keep both paths working — building this repo, and building an
ordinary distribution that consumes it.

## Commands

```sh
prove -lr t                     # unit tests (only t/00-load.t, generated)
prove -lr xt                    # author + release tests — the real test suite
prove -lv xt/author/perlcritic.t   # a single test, verbose
dzil build                      # build; also regenerates project files (see below)
dzil test                       # build, run t/*.t, then xt from the project
dzil release                    # full release chain (checks, TestRelease, UploadToCPAN, tag, push)
perltidy -pro=.perltidyrc lib/...  # .perltidyrc uses --backup-and-modify-in-place
```

CI (`.github/workflows/test.yml`) is exactly `prove -lr t` + `prove -lr xt` after
`cpanm --installdeps --with-develop .`.

The `xt` tests use [XT::Files](https://metacpan.org/pod/XT::Files) and pick up
`.xtfilesrc` from the project root, so run them from the repo root.
`xt/author/perlcritic.t` merges `xt/author/perlcriticrc` with `-code` (modules
and scripts) and `-tests` (test files) overlays.

## Generated files — do not hand-edit

Two distinct categories, both easy to clobber:

1. **Produced by `dzil build`/`dzil release` and copied back into the project**
   by `Author::SKIRMESS::CopyAllFilesFromDistributionToProject`:
   `cpanfile`, `README.md`, `LICENSE`, `t/00-load.t` (and in consuming projects
   also `CONTRIBUTING`, `Makefile.PL`, `META.*`, `README`). To change these,
   change what generates them and re-run `dzil build`. In particular `cpanfile`
   is computed from `AutoPrereqs` + `dist.ini` + the bundle's own cpanfile — never
   edit it by hand.

2. **Shared across the author's repos** and marked
   `# Automatically generated file; DO NOT EDIT.`: everything under `xt/`,
   `.perltidyrc`, `.xtfilesrc`, `xt/author/perlcriticrc*`, `xt/release/*.config`.
   These originate outside this repository and are synced in (see the "update
   shared files" commits). Editing them here diverges from the shared source.

`dist.ini` deliberately contains almost nothing — everything lives in the bundle.
`Git::GatherDir` excludes `CLAUDE.md` and `dist.ini` from the distribution.

## Architecture

`lib/Dist/Zilla/PluginBundle/Author/SKIRMESS.pm` is one long ordered
`configure()` that adds ~60 plugins; **order matters** and the comments above
each `add_plugins` call explain why. The non-obvious machinery:

- **Prereq juggling.** `AutoPrereqs` runs twice: once for the dist, once
  (`AutoPrereqs/WithAuthorAndReleaseTests`) including the project's `xt` tests via
  a custom `FinderCode` finder, because `xt` is *not* shipped in the dist.
  Inline `Code::PrereqSource` plugins then stash the develop prereqs into lexicals
  (`$extended_requires`, `$develop_requires_prereqs`) and strip them from the
  dist, so the project `cpanfile` carries them while `META.*` does not.
- **Extended prereqs → `dynamic_config`.** If smoker (`xt`) prereqs exist, the
  `MetaYAML/RemoveChurn` and `MetaJSON/RemoveChurn` mungers set `dynamic_config`,
  and `Author::SKIRMESS::MakeMaker::Awesome` teaches the generated `Makefile.PL`
  to add those requirements when `AUTOMATED_TESTING` is set.
- **Churn removal.** Version strings and serialization backends are stripped from
  `META.*` and comments from `MANIFEST` so rebuilds produce no spurious diffs.
  Keep this property when touching those mungers.
- **Core-dependency reporting.** Two `Code::AfterBuild` plugins log every
  runtime/configure dependency with the Perl release that first cored it, and
  loudly flag test dependencies that are not core.
- **License injection.** `AddLicenseToDistFiles` rewrites every `.pm`/`.pl`/`.t`/
  `.pod`/`bin/` file at build time into a fixed shape: shebang, vim modeline,
  full ISC license as comments, `use 5.xxx; use strict; use warnings;`, then
  `package`. `_add_license_to_perl_file` is *fatal* on anything unexpected before
  the package statement — new source files must follow that layout (copy an
  existing module).
- **`Local::Software::License::ISC`** supplies the ISC license via
  `Code::LicenseProvider`; `CheckCopyrightYear` whitelists only FreeBSD and this
  ISC class, and **fails the build unless `copyright_year` in `dist.ini` ends in
  the current year** — expect to bump `2017-<year>` at the start of each year.
- **`xt` handling.** `RunExtraTests::FromProject` runs the project's `xt` tests
  twice — against the build dir (`BUILD_TESTING=1`) and against the project
  (`PROJECT_TESTING=1`) — with a `skip_project` list for tests that only make
  sense on a built dist.
- **POD contract.** `UpdatePod` rewrites the VERSION/SUPPORT/AUTHOR sections of
  every `lib/` and `bin/` file and enforces `=head1` order:
  NAME, VERSION, [SYNOPSIS, DESCRIPTION, USAGE|OPTIONS/SUBCOMMANDS/EXIT STATUS,
  EXAMPLES, ENVIRONMENT, RATIONALE, SEE ALSO], SUPPORT, AUTHOR, [CONTRIBUTORS].
  `COPYRIGHT AND LICENSE` is forbidden (the license is in the header comment).
  Repository/issue URLs come from `Dist::Zilla::Role::Author::SKIRMESS::Resources`.
- **`CheckFilesInDistribution`** asserts the built tarball contains exactly the
  expected files — adding a top-level file to the dist means updating its
  `required_file` list in the bundle.

## Conventions for new code

- Plugins live under `lib/Dist/Zilla/Plugin/Author/SKIRMESS/`, are Moose classes
  consuming the relevant `Dist::Zilla::Role::*`, end with
  `__PACKAGE__->meta->make_immutable;` and `1;`, use `namespace::autoclean`, and
  carry `our $VERSION = '1.000'` (`xt/author/test-version.t` requires all
  versions to be identical; `ReversionOnRelease` bumps them together).
- `t/00-load.t` is regenerated by `Author::SKIRMESS::Test::Load`, so a new module
  is picked up automatically by `dzil build` — not by editing the test.
- Perl::Critic runs at severity 1 with `only = 1` and `profile-strictness = fatal`;
  the enabled policy set is large and includes StricterSubs, Moose, Community and
  Pulp policies. Prefer fixing over `## no critic`, and when unavoidable annotate
  the specific policy (unrestricted `## no critic` is itself a violation).
- One-off behaviour that would need a whole plugin is usually written inline as a
  `Code::FileMunger` / `Code::AfterBuild` / `Code::PrereqSource` closure inside
  `configure()`; follow that pattern rather than adding a module for small tweaks.

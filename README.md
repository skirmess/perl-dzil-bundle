# NAME

Dist::Zilla::PluginBundle::Author::SKIRMESS - Dist::Zilla configuration the way SKIRMESS does it

# VERSION

Version 1.000

# SYNOPSIS

## Create a new dzil project

Create a new repository on Github and clone it.

    $ git submodule add ../dzil-inc.git
    $ git commit -m 'added Author::SKIRMESS plugin bundle as git submodule'

    # in dist.ini
    [lib]
    lib = dzil-inc/lib

    [@Author::SKIRMESS]
    :version = 1.000

## Clone a project which already contains this submodule

    $ git clone https://github.com/skirmess/...
    $ git submodule update --init

    # To update dzil-inc
    $ cd dzil-inc && git checkout master

## Update the submodule

    $ cd dzil-inc && git pull

# DESCRIPTION

This is a [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) PluginBundle.

The bundle will not be released on CPAN, instead it is designed to be
included as Git submodule in the project that will use it.

# USAGE

To use this PluginBundle, include it as Git submodule in your project and
add it to your dist.ini. You can provide the following options:

- `appveyor_earliest_perl` - Earliest version of Perl to use on AppVeyor.
(default: ci\_earliest\_perl)
- `appveyor_test_on_cygwin` - Test with Cygwin 32 bit on AppVeyor. (default:
true)
- `appveyor_test_on_cygwin64` - Test with Cygwin 64 bit on AppVeyor. (default:
true)
- `appveyor_test_on_strawberry` - Test with Strawberry Perl on AppVeyor.
(default: true)
- `ci_earliest_perl` - The earliest version of Perl to test on Travis CI and
AppVeyor. (default: 5.8)
- `debug` - Enables debug output of the Bundle itself (unfortunately the
status of `dzil -v` is unknown to a plugin bundle). (default: false)
- `set_script_shebang` - This indicates whether `SetScriptShebang` should be
used or not. (default: true)

# SUPPORT

## Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at [https://github.com/skirmess/dzil-inc/issues](https://github.com/skirmess/dzil-inc/issues).
You will be notified automatically of any progress on your issue.

## Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.

[https://github.com/skirmess/dzil-inc](https://github.com/skirmess/dzil-inc)

    git clone https://github.com/skirmess/dzil-inc.git

# AUTHOR

Sven Kirmess <sven.kirmess@kzone.ch>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2017-2021 by Sven Kirmess.

This is free software, licensed under:

    The (two-clause) FreeBSD License

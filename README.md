# NAME

Dist::Zilla::PluginBundle::Author::SKIRMESS - Dist::Zilla configuration the way SKIRMESS does it

# VERSION

Version 1.000

# SYNOPSIS

## Create a new dzil project

Create a new repository on Github, clone it, and add the following to
`dist.ini`:

    [Git::Checkout]
    repo = https://github.com/skirmess/perl-dzil-bundle.git
    push_url = git@github.com:skirmess/perl-dzil-bundle.git
    dir = dzil-bundle

    [lib]
    lib = dzil-bundle/lib

    [@Author::SKIRMESS]
    :version = 1.000

# DESCRIPTION

This is a [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) PluginBundle.

The bundle will not be released on CPAN, instead it is designed to be
used with the Git::Checkout plugin in the project that will use it.

# USAGE

This PluginBundle supports the following option:

- `set_script_shebang` - This indicates whether `SetScriptShebang` should be
used or not. (default: true)

# SUPPORT

## Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at [https://github.com/skirmess/perl-dzil-bundle/issues](https://github.com/skirmess/perl-dzil-bundle/issues).
You will be notified automatically of any progress on your issue.

## Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.

[https://github.com/skirmess/perl-dzil-bundle](https://github.com/skirmess/perl-dzil-bundle)

    git clone https://github.com/skirmess/perl-dzil-bundle.git

# AUTHOR

Sven Kirmess <sven.kirmess@kzone.ch>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2017-2021 by Sven Kirmess.

This is free software, licensed under:

    The (two-clause) FreeBSD License

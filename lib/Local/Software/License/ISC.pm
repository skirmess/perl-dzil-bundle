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

package Local::Software::License::ISC;

our $VERSION = '1.000';

use parent 'Software::License';

sub fulltext {
    my ($self) = @_;

    return 'Copyright (c) ' . $self->year . q{ } . $self->_dotless_holder . "\n\n" . $self->license;
}

sub meta_name {
    return 'open_source';
}

sub meta2_name {
    return 'open_source';
}

sub name {
    return 'The ISC License';
}

sub url {
    return 'about:blank';
}

1;

__DATA__
__LICENSE__
Permission to use, copy, modify, and distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
__END__

=pod

=encoding UTF-8

=head1 NAME

Local::Software::License::ISC - The ISC License

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

=cut
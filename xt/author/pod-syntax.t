#!perl

use 5.006;
use strict;
use warnings;

# generated by Dist::Zilla::Plugin::Author::SKIRMESS::RepositoryBase 0.033

use Test::Pod 1.26;

use lib::relative '../lib';
use Local::TestsDirs;

all_pod_files_ok( grep { -d } qw( bin lib ), Local::TestsDirs::tests_dirs() );

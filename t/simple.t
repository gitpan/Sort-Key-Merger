#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;

use Sort::Key::Merger qw(nkeymerger);

sub make_key ($) { $_[0] }

sub value_key {
    if (@$_) {
        my $v = shift @$_;
        return ($v, make_key($v))
    }
    ()
}

my @srcs = ([1, 5, 7, 9], [1, 1, 1, 1, 1], [ 2, 2, 2, 3], [34, 45], [], [-1, 100]);

my @sorted = sort { $a <=> $b } map { @$_ } @srcs;

my $merger = nkeymerger \&value_key, @srcs;

my @ksm = $merger->(-1);

is_deeply(\@ksm, \@sorted);

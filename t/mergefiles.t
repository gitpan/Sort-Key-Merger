#!/usr/bin/perl

use strict;
use warnings;

use constant sizes => 1, 4, 32, 128;

use Test::More tests => 30;

use Sort::Key::Merger qw(filekeymerger fileikeymerger filenkeymerger);
use Sort::Key qw(ikeysort);
use Scalar::Quote ':short';

my $merger1 = filenkeymerger { (split)[0] } qw(t/data1 t/data2 t/data3);
my $merger2 = filenkeymerger{ (split)[0] } qw(t/data4);

my (@all1, @all2, $lkey);
while (defined (my $current = $merger1->())) {
    push @all1, $current;
    my $key = (split(" ", $current))[0];

    ok($key >= $lkey, "sorted") if (defined $lkey);

    $lkey=$key;
}

@all1 = sort @all1;
@all2 = sort $merger2->();

is_deeply(\@all1, \@all2, "all");


__END__

my @s1=&$merger1;
my @s2=&$merger2;

if (my ($a, $b)=D("@s1", "@s2", -10, 60)) {
    print "$a ne\n$b\n"
}

is_deeply(\@s1, \@s2);

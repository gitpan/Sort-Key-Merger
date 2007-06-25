package Sort::Key::Merger;

our $VERSION = '0.10_02';

use strict;
use warnings;
use Carp;

use Sort::Key::Types;
our @CARP_NOT = qw(Sort::Key::Types);

# use Data::Dumper qw(Dumper);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(keymerger nkeymerger ikeymerger ukeymerger
                    rkeymerger rnkeymerger rikeymerger rukeymerger
		    filekeymerger nfilekeymerger ifilekeymerger ufilekeymerger
		    rfilekeymerger rnfilekeymerger rifilekeymerger rufilekeymerger);

require XSLoader;
XSLoader::load('Sort::Key::Merger', $VERSION);

use constant STR_SORT => 0;
use constant LOC_STR_SORT => 1;
use constant NUM_SORT => 2;
use constant INT_SORT => 3;
use constant UINT_SORT => 4;
use constant REV_SORT => 128;


use constant VALUE => 0;
use constant FILE => 1;
use constant SCRATCHPAD => 2;
use constant RS => 2;
use constant KEY0 => 3;

my ($int_hints, $locale_hints);
BEGIN {
    use integer;
    $int_hints = $integer::hint_bits || 0x1;
    use locale;
    $locale_hints = $locale::hint_bits || 0x4;
}

sub _make_merger {
    my $types = shift;
    my $typessub = shift;
    my $vkgen = shift;
    my $typeslen = length $types;
    my $typesu = "$types\x04";
    my @src;
    my $i = 0;
    for (@_) {
	my $scratchpad;
	if (my ($v, @k) = &{$vkgen}($scratchpad)) {
            if ($typessub) {
                @k = $typessub->(@k);
            }
            else {
                @k == $typeslen
                    or croak "wrong number of keys generated (expected "
                        .($typeslen - 1).", returned ".(@k - 1).")";
            }
	    unshift @src, [$v, $_, $scratchpad, @k, $i++];
	    _resort($typesu, \@src);
	}
    }
    sub {
        my $max = @_ ? $_[0] : 1;
        my @ret;
        while (@src and $max--) {
            my $src = $src[0];
            push @ret, $src->[VALUE];
            for ($src[0][FILE]) {
                if (my ($v, @k) = &{$vkgen}($src->[SCRATCHPAD])) {
                    if ($typessub) {
                        @k = $typessub->(@k);
                    }
                    else {
                        @k == $typeslen
                            or croak "wrong number of keys generated (expected "
                                .($typeslen - 1).", returned ".(@k - 1).")";
                    }
                    $src->[VALUE] = $v;
                    splice @$src, KEY0, $typeslen, @k;
                    _resort($typesu, \@src);
                }
                else {
                    shift @src;
                }
	    }
	}
        wantarray ? @ret : $ret[-1];
    };
}

sub multikeymerger (&@) {
    my $vkgen = shift;
    my $types = shift;

    ref($types) eq 'ARRAY'
        or croak "Usage: \$merger = multikeymerger { value_key() } \\\@types, \@args";

    my $ptypes = Sort::Key::Types::combine_types(@$types);
    my $typessub = Sort::Key::Types::combine_sub('@_', undef, @$types);

    _make_merger($ptypes, $typessub, $vkgen, @_);
}

sub keymerger (&@) {
    my $sort = ((caller(0))[8] & $locale_hints)
	? LOC_STR_SORT : STR_SORT;
    _make_merger( pack(C => $sort), undef, @_ )
}

sub rkeymerger (&@) {
    my $sort = ((caller(0))[8] & $locale_hints)
	? LOC_STR_SORT : STR_SORT;
    _make_merger( pack(C => $sort|REV_SORT), undef, @_ )
}

sub nkeymerger (&@) {
    my $sort = ((caller(0))[8] & $int_hints)
	? INT_SORT : NUM_SORT;
    _make_merger( pack(C => $sort), undef, @_ )
}

sub rnkeymerger (&@) {
    my $sort = ((caller(0))[8] & $int_hints)
	? INT_SORT : NUM_SORT;
    _make_merger( pack(C => $sort|REV_SORT), undef, @_ )
}


sub ikeymerger (&@) {
    _make_merger( pack(C => UINT_SORT), undef, @_ )
}

sub rikeymerger (&@) {
    _make_merger( pack(C => UINT_SORT|REV_SORT), undef, @_ )
}

sub ukeymerger (&@) {
    _make_merger( pack(C => UINT_SORT), undef, @_ )
}

sub rukeymerger (&@) {
    _make_merger( pack(C => UINT_SORT|REV_SORT), undef, @_ )
}

sub _make_file_merger {
    my $types = shift;
    my $kgen = shift;
    my $typeslen = length $types;
    my $typesu = "$types\x04";
    my @src;
    my $i = 0;
    for my $file (@_) {
	my $fh;
	if (UNIVERSAL::isa($file, 'GLOB')) {
	    $fh = $file;
	}
	else {
	    open $fh, '<', $file
		or croak "unable to open '$file'";
	}
	local $/ = $/;
	local $_;
	while(<$fh>) {
            if (my @k = $kgen->()) {
                @k == $typeslen
                    or croak "wrong number of return values from merger callback, $typeslen expected, "
                        . scalar(@k) . " found";
		unshift @src, [$_, $fh, $/, @k, $i++];
		_resort($typesu, \@src);
		last;
	    }
	}
    }

    my $gen;
    $gen = sub {
	if (wantarray) {
	    my @all;
            my $max = @_ ? $_[0] : 1;
	    while((!defined $max or $max--) and @src) {
		push @all, scalar(&$gen);
	    }
	    return @all;
	}
	else {
	    if (@src) {
		my $src = $src[0];
		my $old_v = $src->[VALUE];
		local *_ = \($src->[VALUE]);
		local */ = \($src->[RS]);   # emacs syntax higlighting breaks here/;
		my $fh = $src->[FILE];
		while(<$fh>) {
                    if (my @k = &{$kgen}) {
                        @k == $typeslen
                            or croak "wrong number of return values from merger callback, $typeslen expected, "
                                . scalar(@k) . " found";
                        $src->[VALUE] = $_;
                        splice @$src, KEY0, $typeslen, @k;
                        _resort($typesu, \@src);
                        return $old_v;
                    }
		}
		shift @src;
		return $old_v;
	    }
	    return undef
	}
    };
}

sub filekeymerger (&@) {
    my $sort = ((caller(0))[8] & $locale_hints)
	? LOC_STR_SORT : STR_SORT;
    _make_file_merger( pack(C => $sort), @_ )
}

sub rfilekeymerger (&@) {
    my $sort = ((caller(0))[8] & $locale_hints)
	? LOC_STR_SORT : STR_SORT;
    _make_file_merger( pack(C => $sort|REV_SORT), @_ )
}

sub nfilekeymerger (&@) {
    my $sort = ((caller(0))[8] & $int_hints)
	? INT_SORT : NUM_SORT;
    _make_file_merger( pack(C => $sort), @_ )
}

sub rnfilekeymerger (&@) {
    my $sort = ((caller(0))[8] & $int_hints)
	? INT_SORT : NUM_SORT;
    _make_file_merger( pack(C => $sort|REV_SORT), @_ )
}

sub ifilekeymerger (&@) {
    _make_file_merger( pack(C => INT_SORT), @_ )
}

sub rifilekeymerger (&@) {
    _make_file_merger( pack(C => INT_SORT|REV_SORT), @_ )
}

sub ufilekeymerger (&@) {
    _make_file_merger( pack(C => INT_SORT), @_ )
}

sub rufilekeymerger (&@) {
    _make_file_merger( pack(C => INT_SORT|REV_SORT), @_ )
}


1;
__END__

=head1 NAME

Sort::Key::Merger - Perl extension for merging sorted things

=head1 SYNOPSIS

  use Sort::Key::Merger qw(keymerger);

  sub line_key_value {

      # $_[0] is available as a scratchpad that persist
      # between calls for the same $_;
      unless (defined $_[0]) {
          # so we use it to cache the file handle when we
	  # open a file on the first read
	  open $_[0], "<", $_
	      or croak "unable to open $_";
      }

      # don't get confused by this while loop, it's only
      # used to ignore empty lines
      my $fh = $_[0];
      local $_; # break $_ aliasing;
      while (<$fh>) {
	  next if /^\s*$/;
	  chomp;
	  if (my ($key, $value) = /^(\S+)\s+(.*)$/) {
	      return ($value, $key)
	  }
	  warn "bad line $_"
      }

      # signals the end of the data by returning an
      # empty list
      ()
  }

  # create a merger object:
  my $merger = keymerger { line_key_value } @ARGV;

  # sort and write the values:
  my $value;
  while (defined($value=$merger->())) {
      print "value: $value\n"
  }


=head1 WARNING!!!

Several backward imcompatible changes has been introduced in version
0.10:

    - filekeymerger callbacks are now called on list context
    - order of return values on keymerger callback has changed
    - in list context only the next value is returned by default
      instead of all the remaining ones

=head1 DESCRIPTION

Sort::Key::Merger merges presorted collections of data based on some
(calculated) keys.

Given 

=head2 FUNCTIONS

The following functions are available from this module:

=over 4

=item keymerger { GENERATE_VALUE_KEY_PAIR($_) } @sources;

creates a merger object for the given C<@sources> collections.

Every item in C<@source> is aliased by $_ and then the user defined
subroutine C<GENERATE_VALUE_KEY_PAIR> called. The result from that
callback should be a (value, key) pair. Keys are used to determine the
order in which the values are sorted.

C<GENERATE_VALUE_KEY_PAIR> can return an empty list to indicate that a
source has become exhausted.

The result from C<keymerger> is another subroutine that works as a
generator. It can be called as:

  my $next = $merger->();

  my @next = $merger->($n);


In scalar context it returns the next value or undef if all the
sources have been exhausted. In list context it returns the next $n
values (1 is used as the deault value for $n).

If your data can contain undef values, you should iterate over the
sorted values as follows:

  my $merger = keymerger ...;

  while (my ($next) = $merger->()) {
     # do whatever with $next
     # ...
  }

Passing -1 makes the function return all the remaining values:

  my @remaining = $merger->(-1);

NOTE: an additional argument is passed to the
C<GENERATE_VALUE_KEY_PAIR> callback in C<$_[0]>. It is to be used as a
scrachpad, its value is associated to the current source and will
perdure between calls from the same generator, i.e.:

  my $merger = keymerger {

      # use $_[0] to cache an open file handler:
      $_[0] or open $_[0], '<', $_
	  or croak "unable to open $_";

      my $fh = $_[0];
      local $_;
      while (<$fh>) {
	  chomp;
	  return $_ => $_;
      }
      ();
  } ('/tmp/foo', '/tmp/bar');


This function honours the C<use locale> pragma.

=item nkeymerger { GENERATE_VALUE_KEY_PAIR($_) } @sources

is like C<keymerger> but compares the keys numerically.

This function honours the C<use integer> pragma.

=item ikeymerger

Similar to C<keymerger> but Compares the keys as integers.

=item ukeymerger

Compares the keys as unsigned integers.

=item rkeymerger

=item rnkeymerger

=item rikeymerger

=item rukeymerger

performs the sorting in reverse order.

=item filekeymerger { generate_key } @files;

returns a merger subroutine that returns lines read from C<@files>
sorted by the keys that C<generate_key> generates.

C<@files> can contain file names or handles for already open files.

C<generate_key> is called with the line just read on C<$_> and has to
return the sorting key for it. If its return value is C<undef> the
line is ignored.

The line can be modified inside C<generate_key> changing C<$_>, i.e.:

  my $merger = filekeymerger {
      chomp($_); #             <== here
      return undef if /^\s*$/;
      substr($_, -1, 10)
  } @ARGV;


Finally, C<$/> can be changed from its default value to read the files
in chunks other than lines.

The return value from this function is a subroutine reference that on
successive calls returns the sorted elements in the same fashion as
the iterator returned from C<keymerger>.

  my $merger = filekeymerger { (split)[0] } @ARGV;
  while (my ($next) = $merger->(1)) {
    ...
  }


This function honours the C<use locale> pragma.

=item nfilekeymerger { generate_key } @files;

is like C<filekeymerger> but the keys are compared numerically.

This function honours the C<use integer> pragma.

=item ifilekeymerger

similar to filekeymerger bug compares the keys as integers.

=item ufilekeymerger

similar to filekeymerger bug compares the keys as unsigned integers.

=item rfilekeymerger

=item rnfilekeymerger

=item rifilekeymerger

=item rufilekeymerger

perform the sorting in reverse order.

=item multikeymerger { GENERATE_VALUE_KEYS_LIST($_) } \@types, @sources

This function generates a multikey merger.

C<GENERATE_VALUE_KEYS_LIST> should return a list with the next value
from the source passed in C<$_> and the sorting keys.

C<@types> is an array with the key sorting types (ee L<Sort::Key>
multikey sorting documentation for a discussion on the supported
types).

For instance:

  my $merger = multikeymerger {
      my $v = shift $@_;
      my $name = $v->name;
      my $age = $v->age;
      ($v, $age, $name)
  } [qw(-integer string)], @data_sources;

  while (my ($next) = $merger->()) {
      print "$next\n";
  }

=back

=head1 SEE ALSO

L<Sort::Key>, L<Sort::Key::External>, L<locale>, L<integer>, perl core
L<sort> function.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005, 2007 by Salvador FandiE<ntilde>o,
E<lt>sfandino@yahoo.comE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

=cut

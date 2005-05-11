package Sort::Key::Merger;

our $VERSION = '0.05';

use strict;
use warnings;
use Carp;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(keymerger ikeymerger nkeymerger
		    filekeymerger fileikeymerger filenkeymerger);

sub _resort ($\@) {
    my $le=shift;
    my $src=shift;
    if (@$src > 1){
	my $k = $src->[0][0];
	return if $le->($k, $src->[1][0]);

	my $i;
	for ($i=2; $i<@$src; $i++) {
	    last if ($le->($k, $src->[$i][0]));
	}
	$i--;
	@{$src}[0..$i]=(@{$src}[1..$i], ${$src}[0]);
    }
}

sub _merger_maker {
    my ($le, $sub, @args)=@_;
    my @src;
    for (@args) {
	my $scratch;
	if (my ($k, $v) = &{$sub}($scratch)) {
	    unshift @src, [$k, $v, $_, $scratch];
	    _resort($le, @src);
	}
    }
    my $gen;
    $gen = sub {
	if (wantarray) {
	    my @all;
	    my $next;
	    while(defined($next = &$gen)) {
		push @all, $next;
	    }
	    return @all;
	}
	else {
	    my $old_v;
	    if (@src) {
		$old_v=$src[0][1];
		for ($src[0][2]) {
		    if (my @kv = &{$sub}($src[0][3])) {
			@kv == 2 or croak 'wrong number of return values from merger callback';
			$src[0][0] = $kv[0];
			$src[0][1] = $kv[1];
			_resort($le, @src);
		    }
		    else {
			shift @src;
		    }
		}
	    }
	    return $old_v;
	}
    };
}

sub keymerger (&@) {  _merger_maker(sub { $_[0] le $_[1]}, @_) }

sub ikeymerger (&@) {  _merger_maker(sub { int($_[0]) <= int($_[1])}, @_) }

sub nkeymerger (&@) {  _merger_maker(sub { $_[0] <= $_[1]}, @_) }

# use Data::Dumper;

sub _file_merger_maker {
    my ($le, $sub, @args)=@_;
    my @src;
    for my $file (@args) {
	my $fh;
	if (UNIVERSAL::isa($file, 'GLOB')) {
	    $fh=$file;
	}
	else {
	    open $fh, '<', $file
		or croak "unable to open '$file'";
	}
	local $/ = $/;
	local $_;
	while(<$fh>) {
	    if (defined(my $k = &{$sub})) {
		unshift @src, [$k, $_, $fh, $/];
		_resort($le, @src);
		last;
	    }
	}
    }

    # print Dumper(\@src);

    my $gen;
    $gen = sub {
	if (wantarray) {
	    my @all;
	    while(@src) {
		push @all, scalar(&$gen);
	    }
	    return @all;
	}
	else {
	    if (@src) {
		my $src=$src[0];
		my $old_v=$src->[1];
		local *_ = \($src->[1]);
		local */ = \($src->[3]);   # emacs syntax higlighting breaks here/;
		my $fh=$src->[2];
		while(<$fh>) {
		    if (defined ($src->[0]=&{$sub})) {
			_resort($le, @src);
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

sub filekeymerger (&@) { _file_merger_maker(sub { $_[0] le $_[1] }, @_) }

sub fileikeymerger (&@) { _file_merger_maker(sub { int($_[0]) <= int($_[1]) }, @_) }

sub filenkeymerger (&@) { _file_merger_maker(sub { $_[0] <= $_[1] }, @_) }


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
	      return ($key, $value)
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



=head1 DESCRIPTION

Sort::Key::Merger allows to merge presorted collections of I<things>
based on some (calculated) key.

=head2 EXPORT

None by default.

The functions described below can be exported requesting so
explicitly, i.e.:

  use Sort::Key::Merger qw(keymerger);


=head2 FUNCTIONS

=over 4

=item keymerger { generate_key_value_pair } @sources;

merges the (presorted) generated values sorted by their keys
lexicographically.

Every item in C<@source> is aliased by $_ and then the user defined
subroutine C<generate_key_value_pair> called. The result from that
subroutine call should be a (key, value) pair. Keys are used to
determine the order in which the values are sorted and returned.

C<generate_key_value_pair> can return an empty list to indicate that a
source has become exhausted.

The result from C<keymerger> is another subroutine that works as a
generator. It can be called as:

  my $next = &$merger;

or

  my $next = $merger->();

In scalar context it returns the next value or undef if all the
sources have been exhausted. In list context it returns all the values
remaining from the sources merged in a sorted list.

NOTE: an additional argument is passed to the
C<generate_key_value_pair> callback in C<$_[0]>. It is to be used as a
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


=item ikeymerger { generate_key_value_pair } @sources

is like C<keymerger> but compares the keys as integers.

=item nkeymerger { generate_key_value_pair } @sources

is like C<keymerger> but compares the keys numerically.

=item filekeymerger { generate_key } @files;

returns a merger subroutine that returns lines read from C<@files>
sorted by the keys that C<generate_key> generates.

C<@files> can contain file names or handles for already open files.

C<generate_key> is called with the line just read on C<$_> and has to
return the sorting key for it. If its return value is C<undef> the
line is ignored.

The line can be modified inside C<generate_key> changing C<$_>, i.e.:

  my $merger = filekeymerger {
      chomp($_); #             <-- here
      return undef if /^\s*$/;
      substr($_, -1, 10)
  } @ARGV;


Finally, C<$/> can be changed from its default value to read the files
in chunks other than lines.

The return value from this function is a subroutine reference that on
successive calls returns the sorted elements; or all elements in one
go when called in list context, i.e.:

  my $merger = filekeymerger { (split)[0] } @ARGV;
  my @sorted = $merger->();

=item fileikeymerger { generate_key } @files;

is like C<filekeymerger> but the keys are compared as integers.

=item filenkeymerger { generate_key } @files;

is like C<filekeymerger> but the keys are compared numerically.

=back

=head1 SEE ALSO

L<Sort::Key>

=head1 AUTHOR

Salvador FandiE<ntilde>o, E<lt>sfandino@yahoo.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Salvador FandiE<ntilde>o.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

=cut

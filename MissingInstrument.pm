# -*- mode: perl -*-
package MissingInstrument;
use strict;
use warnings;
use Devel::StackTrace;
use Carp qw(cluck);
use Carp::Always::Color;

# Instantiate a handle as this if we detect that an instrument is missing.
# Any call to it will cause a die.
#
# Setup as "$x=MissingInstrument->new("some name");"
sub new {
  my $class = shift;
  my $self  = {};
  $self->{What} = shift;
  return bless $self, $class;
}
our $AUTOLOAD;

sub AUTOLOAD {
  my $self   = shift;
  my $called = $AUTOLOAD =~ s/.*:://r;
  my $what   = $self->{What};
  cluck( sprintf( "%s\n%s is missing in call to %s.", scalar( localtime(time) ), $what, $called ) );
}

# -*- mode: perl -*-
# perltidy -i=2 -ce -l=100
package CDR;
use Moose::Role;

# This class role exposes a unified CDR interface
has 'loopOrder' => ( is => 'rw', isa => 'Int', default => 2 );

sub cdrInit {
  my $self = shift;
}

sub cdrLoopOrder {
  my $self      = shift;
  my $loopOrder = shift;
  print( STDERR "CDR role: %s called but isn't implemented.\n", ( caller(0) )[3] );
}

sub cdrState {
  my $self = shift;
  my $on   = shift;
  print( STDERR "CDR role: %s called but isn't implemented.\n", ( caller(0) )[3] );
}

sub cdrRate {
  my $self = shift;
  my $freq = shift;
  print( STDERR "CDR role: %s called but isn't implemented.\n", ( caller(0) )[3] );
}

sub cdrLoopBW {
  my $self = shift;
  my $bw   = shift;
  print( STDERR "CDR role: %s called but isn't implemented.\n", ( caller(0) )[3] );
}

sub cdrRelock {
  my $self = shift;
  print( STDERR "CDR role: %s called but isn't implemented.\n", ( caller(0) )[3] );
}

sub cdrLocked {
  my $self = shift;
  print( STDERR "CDR role: %s called but isn't implemented.\n", ( caller(0) )[3] );
  return (0);
}
1;

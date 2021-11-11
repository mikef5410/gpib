# -*- mode: perl -*-
# perltidy -i=2 -ce -l=100
package CDR;

use Moose;
use namespace::autoclean;

# This class wraps a variety of CDRs.
has 'loopOrder' => { is => 'rw', isa => 'INT', default => 2 };

sub init {
  my $self = shift;

}

sub cdrLoopOrder {
  my $self      = shift;
  my $loopOrder = shift;

}

sub cdrState {
  my $self = shift;
  my $on   = shift;

}

sub cdrRate {
  my $self = shift;
  my $freq = shift;

}

sub cdrLoopBW {
  my $self = shift;
  my $bw   = shift;

}

sub relock {
  my $self = shift;
}

sub locked {
  my $self = shift;
  return (0);
}

1;

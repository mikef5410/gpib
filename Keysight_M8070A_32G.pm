# -*- mode: perl -*-
package Keysight_M8070A_32G;
use Moose;
use namespace::autoclean;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

sub init {
  my $self = shift;

  return 0 if ( $self->{VIRTUAL} );

  $self->iconnect();
  $self->iwrite("*RST") if ( $self->{RESET} );    #Get us to default state

  my $err = 'x';                                  # seed for first iteration
                                                  # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /\+0/ );                    # error 0 means buffer is empty
  }
  $self->iwrite("*CLS");
  #
  return 0;

}

sub outputsON {
  my $self = shift;
  my $on   = shift;

  $on = ( $on != 0 );
  $self->iwrite( ":OUTPUT:STATE 'M2.DataOut',", $on );
  $self->globalOutputsON($on);
}

sub globalOutputsON {
  my $self = shift;
  my $on   = shift;

  $on = ( $on != 0 );
  $self->iwrite( ":OUTPUT:GLOBAL:STATE 'M1.System',", $on );
}

sub externalReference {
  my $self = shift;
  my $on   = shift;

  $on = ( $on != 0 );
  if ($on) {
    $self->iwrite(":TRIG:SOURCE 'M1.ClkGen',REFerence");
    $self->iwrite(":TRIG:REF:FREQ 'M1.ClkGen',REF10");
  } else {
    $self->iwrite(":TRIG:SOURCE 'M1.ClkGen',INTernal");
    $self->iwrite(":TRIG:INT:SOURCE 'M1.ClkGen',INTernal");
  }
}

sub getMuxMode {
  my $self = shift;

  my $res = $self->iquery(":SOURCE:CONFigure:MINTegration? 'M2.MuxMode'");
  chomp($res);
  chomp($res);
  my ( $a, $b, $c ) = split( ",", $res );
  return ($a);
}

sub setMuxMode {
  my $self = shift;
  my $mode = shift;    # "NONe|MUX|DMUX|BOTH"

  $self->iwrite(":SOURCE:CONFigure:MINTegration 'M2.MuxMode',$mode");
}

sub PGclockRate {
  my $self  = shift;
  my $clock = shift;
}

__PACKAGE__->meta->make_immutable;
1;

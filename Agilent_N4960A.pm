# -*- mode: perl -*-
package Agilent_N4960A;
use Moose;
use namespace::autoclean;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

sub init {
  my $self = shift;

  return 0 if ( $self->{VIRTUAL} );

  $self->iconnect();
  $self->iwrite("*RST;") if ( $self->{RESET} );    #Get us to default state

  my $err = 'x';                                   # seed for first iteration
                                                   # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /\+0/ );                     # error 0 means buffer is empty
  }
  $self->iwrite("*CLS;");
  #
  return 0;

}

#Set/Get CW frequency in Hz
sub freq {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":SOURCE:FREQUENCY:CW?") );
  } else {
    $self->iwrite(":SOURCE:FREQUENCY:CW $val;");
    $self->iOPC();
  }
}

#Set/Get Output Amplitude in Volts
sub amplSubrate {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":OUTSubrate:Amplitude?") );
  } else {
    $self->iwrite(":OUTSubrate:Amplitude $val V;");
    $self->iOPC();
  }
}

sub outputSubrateState {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":OUTSubrate:OUTPUT?") );
  } else {
    my $s = "OFF";
  SW: {
      if ( $val =~ /on/i )  { $s = "ON";  last SW; }
      if ( $val =~ /off/i ) { $s = "OFF"; last SW; }
    }
    $self->iwrite(":OUTSubrate:OUTPUT $s;");
    $self->iOPC();
  }
}

sub dividerSubrate {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":OUTSubrate:Divider?") );
  } else {
    $self->iwrite(":OUTSubrate:Divider $val ;");
    $self->iOPC();
  }
}

__PACKAGE__->meta->make_immutable;
1;

# -*- mode: perl -*-
package Agilent_N5182A;
use Moose;
use namespace::autoclean;
use Time::HiRes qw(sleep usleep gettimeofday tv_interval);
use Carp qw(cluck longmess shortmess);

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

#Set/Get CW frequency in Hz
sub freq {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":SOURCE:FREQUENCY:CW?") );
  } else {
    $self->iwrite(":SOURCE:FREQUENCY:CW $val;");
    $self->iOPC(3);
  }
}

#Set/Get Output Amplitude in dBm
sub ampl {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":POWER?") );
  } else {
    $self->iwrite(":POWER $val dBm;");
    $self->iOPC(3);
  }
}

sub outputState {
  my $self = shift;
  my $val  = shift;

  if ( !defined($val) ) {
    return ( $self->iquery(":OUTP?") );
  } else {
    my $s = 0;
  SW: {
      if ( $val =~ /on/i )  { $s = 1; last SW; }
      if ( $val =~ /off/i ) { $s = 0; last SW; }
      $s = ( $val != 0 );
    }
    $self->iwrite(":OUTPUT:STATE $s;");
    $self->iOPC(3);
  }
}

__PACKAGE__->meta->make_immutable;
1;

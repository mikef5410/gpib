# -*- mode: perl -*-
#perltidy -i=2 -ce

package Agilent_N4903A;
use Moose;
use namespace::autoclean;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

our $SYNCLOSS        = ( 0x1 << 10 );
our $DATALOSS        = (0x1);
our $CLOCKLOSS       = ( 0x1 << 5 );
our $PROTDATAIN      = ( 0x1 << 6 );
our $PROTPGDLYCTRLIN = ( 0x1 << 7 );
our $UNCAL           = ( 0x1 << 8 );
our $PROTECTIONCKTS  = ( 0x1 << 11 );
our $SYMBOLMODE      = ( 0x1 << 12 );

sub amplitude_cm {
  my $self = shift;
  my $ampl = shift;
  my $offs = shift;

  $self->iwrite( sprintf( ":SOUR:VOLT:AMPL %g; OFFS %g", $ampl, $offs ) );
  my $trash = $self->iOPC();
}

sub autoAlign {
  my $self = shift;

  my $result;
  $self->iwrite(":SENS1:EYE:ALIGN:AUTO ONCE;");
  while (1) {
    $result = $self->iquery(":SENS1:EYE:ALIGN:AUTO?;");
    last if ( $result =~ /SUCCESSFUL|FAILED|ABORTED/ );
    sleep(0.5);
  }
  return (1) if ( $result =~ /SUCCESSFUL/ );
  return (0);
}

sub isSynchronized {
  my $self = shift;

  my $res;
  $res = $self->iquery(":STATUS:QUESTIONABLE:CONDITION?;");
  return ( ( $res && $SYNCLOSS ) == 0 );
}

sub gateOn {
  my $self = shift;
  my $on   = shift;

  my $res;
  if ( !defined($on) ) {
    $res = $self->iquery(":STATUS:OPERATION:CONDITION?;");
    return ( ( $res & 0x1 << 4 ) != 0 );
  } else {
    $on = ( $on != 0 ) ? 1 : 0;
    $self->iwrite(":SENSE1:GATE:STATE $on;");
    return (1);
  }
}

sub BERtime {
  my $self   = shift;
  my $period = shift;    #seconds

  my $count = 100;
  my $res;
  $self->iwrite(":SENSE1:GATE:STATE 0;");
  $self->iwrite(":SENSE1:ERMode BER;:SENSE1:GATE:MODE MAN;");
  $self->iwrite(":SENSE1:GATE:MODE SINGLE;");
  $self->iwrite( sprintf( ":SENSE1:GATE:PERIOD:TIME %d;", $period ) );

  do {
    sleep(0.1);
    $res = $self->iquery(":STATUS:QUESTIONABLE:CONDITION?;");
  } while ( ( $res && $SYNCLOSS ) && ( $count-- > 0 ) );
  return (-1) if ( $count <= 0 );
  $self->iwrite(":SENSE1:GATE:STATE 1;");
  sleep( 0.9 * $period );

  do {
    sleep(1);
    $res = $self->iquery(":STATUS:OPERATION:CONDITION?;");
  } while ( $res & 0x1 << 4 );    #Gate on?

  $res = $self->iquery(":STATUS:QUESTIONABLE:CONDITION?;");
  if ( $res != 0 ) { return (-1); }
  $res = $self->iquery(":FETCH:SENSE1:ERATIO?");
  return ( $res + 0.0 );
}

__PACKAGE__->meta->make_immutable;
1;

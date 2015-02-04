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

sub outputsON {
  my $self=shift;
  my $on=shift;

  my $conn="DISCONNECTED";
  if ($on != 0) {
    $conn="CONNECTED";
  }
  $self->iwrite(":OUTPUT1:CENTRAL $conn;");
  $self->iOPC();
}

sub amplitude_cm {
  my $self = shift;
  my $ampl = shift;
  my $offs = shift;

  if ($offs==0) {
    $self->iwrite(":OUTPUT1:COUPLING:AC;");
  } else {
    $self->iwrite(":OUTPUT1:COUPLING:DC;");
  }    
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

sub prbsSet {
  my $self=shift;
  my $prbsPatt=shift;

  $self->iwrite(":SENSE1:PATTERN:TRACK 1;");
  if ($prbsPatt=~/PRB[SN](7|10|11|13|15|23|31)/) {
    $self->iwrite(":SOURCE1:PATTERN:SELECT $prbsPatt;");
  } else {
    $self->throw({err=>"Bad prbs pattern choice"});
  }
  my $res=$self->iOPC();
}

sub clockAmpl_cm {
  my $self=shift;
  my $ampl=shift;
  my $offs=shift;

  if ($offs==0) {
    $self->iwrite(":OUTPUT2:COUPLING:AC;");
  } else {
    $self->iwrite(":OUTPUT2:COUPLING:DC;");
  }
  $self->iwrite(sprintf(":SOURCE2:VOLTAGE:LEVEL:IMMEDIATE:OFFSET %g;",$offs));
  $self->iwrite(sprintf(":SOURCE2:VOLTAGE:LEVEL:IMMEDIATE:AMPLITUDE %g;",$ampl));
  $self->iOPC();
}

sub clockRate {
  my $self=shift;
  my $freq=shift;

  $self->iwrite(sprintf(":SOURCE9:FREQ:CW %g;",$freq));
  $self->iwrite(":SOURCE9:OUTPUT:STATE INT;");
  $self->iOPC();
}

sub subrateDivisor {
  my $self=shift;
  my $div=shift;

  if ($div>=2 && $div<=128) {
    $self->iwrite(sprintf(":SOURCE5:DIVIDER %d;",$div));
  } else {
    $self->throw({err=>"Subrate divisor out of range"});
  }
  $self->iOPC();
}

__PACKAGE__->meta->make_immutable;
1;

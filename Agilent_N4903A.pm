# -*- mode: perl -*-
#perltidy -i=2 -ce

package Agilent_N4903A;
use Moose;
use namespace::autoclean;

## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
## no critic (BitwiseOperators)

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

#Questionable Status Register
our %QSR = (
  DATALOSS        => 0x1,
  CLOCKLOSS       => 0x20,
  PROTDATAIN      => 0x40,
  PROTPGDLYCTRLIN => 0x80,
  UNCAL           => 0x100,
  SYNCLOSS        => 0x400,
  PROTECTIONCKTS  => 0x800,
  SYMBOLMODE      => 0x1000
);

#Status Byte
our %SB = (
  EAV  => 0x4,
  QUES => 0x8,
  MAV  => 0x10,
  ESB  => 0x20,
  SRQ  => 0x40,
  OPER => 0x80
);

#Operation Status Register
our %OSR = (
  OVERHEAT      => 0x8,
  GATEON        => 0x10,
  GATEABORT     => 0x80,
  BITERR        => 0x0100,
  CLKDATACTR    => 0x0800,
  DATATHRALIGN  => 0x1000,
  AUTOALIGN     => 0x2000,
  ERRLOCCAPTURE => 0x4000,
  BLOCKCHANGE   => 0x8000
);

#Protection Ckts Status Register
our %PSR = (
  DATAOUT => 0x1,
  CLKOUT  => 0x2,
  TRIGOUT => 0x4,
  AUXOUT  => 0x8
);

#Clock Loss Status Register
our %CLSR = ( ERRDET => 0x1, PATGEN => 0x2 );

#Standard Event Status Register
our %SER = (
  OPC => 0x1,
  QYE => 0x4,
  DDE => 0x8,
  EXE => 0x10,
  CME => 0x20,
  PON => 0x80
);

#Symbol Mode Status Register
our %SMSR = ( SYMBALIGNLOSS => 0x1, SYMBALIGNDONE => 0x2 );

#Try to make sure we don't leave a lock hanging around.
sub DEMOLISH {
  my $self = shift;

  $self->iunlock();
  return;
}

sub outputsON {
  my $self = shift;
  my $on   = shift;

  my $conn = "DISCONNECTED";
  if ( $on != 0 ) {
    $conn = "CONNECTED";
  }
  $self->iwrite(":OUTPUT1:CENTRAL $conn;");
  $self->iOPC();
}

sub amplitude_cm {
  my $self = shift;
  my $ampl = shift;
  my $offs = shift;

  if ( defined($ampl) && $ampl < 0 ) {
    confess("Amplitude is positive in volts!");
  }

  if ( defined($offs) ) {
    if ( abs($offs) > 3.0 ) {
      confess("Offset is in volts from -3.0V to 3.0V");
    }
    if ( $offs == 0 ) {
      $self->iwrite(":OUTPUT1:COUPLING:AC;");
    } else {
      $self->iwrite(":OUTPUT1:COUPLING:DC;");
    }
  }
SW: {
    if ( defined($offs) && defined($ampl) ) {
      $self->iwrite( sprintf( ":SOUR:VOLT:AMPL %g; OFFS %g;", $ampl, $offs ) );
      last SW;
    }
    if ( defined($offs) && !defined($ampl) ) {
      $self->iwrite( sprintf( ":SOUR:VOLT:OFFS %g;", $ampl, $offs ) );
      last SW;
    }
    if ( !defined($offs) && defined($ampl) ) {
      $self->iwrite( sprintf( ":SOUR:VOLT:AMPL %g;", $ampl, $offs ) );
      last SW;
    }

  }

  my $trash = $self->iOPC();
}

sub amplitude {
  my $self = shift;
  my $ampl = shift;

  $self->amplitude_cm( $ampl, undef );
}

sub vcm {
  my $self = shift;
  my $offs = shift;

  $self->amplitude_cm( undef, $offs );
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
  return ( ( $res && $QSR{SYNCLOSS} ) == 0 );
}

sub gateOn {
  my $self = shift;
  my $on   = shift;

  my $res;
  if ( !defined($on) ) {
    $res = $self->iquery(":STATUS:OPERATION:CONDITION?;");
    return ( ( $res & $OSR{GATEON} ) != 0 );
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
  $self->iwrite(":SENSE1:ERMode:MODE BER;:SENSE1:GATE:MODE MAN;");
  $self->iwrite(":SENSE1:GATE:MODE SINGLE;");
  $self->iwrite( sprintf( ":SENSE1:GATE:PERIOD:TIME %d;", $period ) );

  do {
    sleep(0.1);
    $res = $self->iquery(":STATUS:QUESTIONABLE:CONDITION?;");
  } while ( ( $res && $QSR{SYNCLOSS} ) && ( $count-- > 0 ) );
  return (-1) if ( $count <= 0 );
  $self->iwrite(":SENSE1:GATE:STATE 1;");
  sleep( 0.9 * $period );

  do {
    sleep(1);
    $res = $self->iquery(":STATUS:OPERATION:CONDITION?;");
  } while ( $res & $OSR{GATEON} );    #Gate on?

  $res = $self->iquery(":STATUS:QUESTIONABLE:CONDITION?;");
  if ( $res != 0 ) { return (-1); }
  $res = $self->iquery(":FETCH:SENSE1:ERATIO?");
  return ( $res + 0.0 );
}

sub prbsSet {
  my $self     = shift;
  my $prbsPatt = shift;

  $self->iwrite(":SENSE1:PATTERN:TRACK 1;");
  if ( $prbsPatt =~ /PRB[SN](7|10|11|13|15|23|31)/ ) {
    $self->iwrite(":SOURCE1:PATTERN:SELECT $prbsPatt;");
  } else {
    $self->throw( { err => "Bad prbs pattern choice" } );
  }
  my $res = $self->iOPC();
}

sub prbsSetED {
  my $self     = shift;
  my $prbsPatt = shift;

  if ( $prbsPatt =~ /PRB[SN](7|10|11|13|15|23|31)/ ) {
    $self->iwrite(":SENSEE1:PATTERN:SELECT $prbsPatt;");
  } else {
    $self->throw( { err => "Bad prbs pattern choice" } );
  }
  my $res = $self->iOPC();
}

sub clockAmpl_cm {
  my $self = shift;
  my $ampl = shift;
  my $offs = shift;

  if ( defined($ampl) && $ampl < 0 ) {
    confess("Clock Amplitude is positive in volts!");
  }

  if ( defined($offs) ) {
    if ( abs($offs) > 3.0 ) {
      confess("Clock Offset is in volts from -3.0V to 3.0V");
    }
    if ( $offs == 0 ) {
      $self->iwrite(":OUTPUT2:COUPLING:AC;");
    } else {
      $self->iwrite(":OUTPUT2:COUPLING:DC;");
    }
  }

SW: {
    if ( defined($offs) && defined($ampl) ) {
      $self->iwrite( sprintf( ":SOURCE2:VOLTAGE:LEVEL:IMMEDIATE:OFFSET %g;",    $offs ) );
      $self->iwrite( sprintf( ":SOURCE2:VOLTAGE:LEVEL:IMMEDIATE:AMPLITUDE %g;", $ampl ) );
      last SW;
    }
    if ( defined($offs) && !defined($ampl) ) {
      $self->iwrite( sprintf( ":SOURCE2:VOLTAGE:LEVEL:IMMEDIATE:OFFSET %g;", $offs ) );
      last SW;
    }
    if ( !defined($offs) && defined($ampl) ) {
      $self->iwrite( sprintf( ":SOURCE2:VOLTAGE:LEVEL:IMMEDIATE:AMPLITUDE %g;", $ampl ) );
      last SW;
    }
  }
  $self->iOPC();
}

sub clockAmplitude {
  my $self = shift;
  my $ampl = shift;

  $self->clockAmpl_cm( $ampl, undef );
}

sub clockVcm {
  my $self = shift;
  my $Vcm  = shift;

  $self->clockAmpl_cm( undef, $Vcm );
}

sub clockRate {
  my $self = shift;
  my $freq = shift;

  $self->iwrite( sprintf( ":SOURCE9:FREQ:CW %g;", $freq ) );
  $self->iwrite( sprintf( ":SENSE1:FREQ:CW %g;",  $freq ) );

  #$self->iwrite( sprintf( ":SENSE2:FREQ:CW %g;", $freq ) );
  $self->iwrite(":SENSE2:FREQ:CDR ON;");
  $self->iwrite(":SENSE6:MODE INT;");
  $self->iwrite(":SOURCE9:OUTPUT:STATE INT;");
  $self->iOPC();
}

sub subrateDivisor {
  my $self = shift;
  my $div  = shift;

  if ( $div >= 2 && $div <= 128 ) {
    $self->iwrite( sprintf( ":SOURCE5:DIVIDER %d;", $div ) );
  } else {
    $self->throw( { err => "Subrate divisor out of range" } );
  }
  $self->iOPC();
}

sub defineStraightPatternFile {
  my $self     = shift;
  my $filename = shift;
  my $patt     = shift;    #Packing 1 is the only one that seems to work

  my $size = length($patt);

  my $headerSize = 1;
  $headerSize = 2 if ( $size > 9 );
  $headerSize = 3 if ( $size > 99 );
  $headerSize = 4 if ( $size > 999 );
  $headerSize = 5 if ( $size > 9999 );

  $patt = sprintf( "#%d%d%s", $headerSize, $size, $patt );
  if ( !$filename =~ /'/ ) {
    $filename = "'" . $filename . "'";
  }

  $self->iwrite(":SENSE1:PATTERN:TRACK ON;");
  $self->iwrite(":SOURCE1:PATTERN:UFILE:USE $filename, STRaight;");
  $self->iwrite(":SOURCE1:PATERN:FORMAT:DATA PACKED,1;");
  $self->iwrite(":SOURCE1:PATTERN:UFILE:DATA A, $filename, $patt ;");
  my $res = $self->iOPC();
}

sub selectPatternFile {
  my $self     = shift;
  my $filename = shift;

  if ( !$filename =~ /'/ ) {
    $filename = "'" . $filename . "'";
  }

  $self->iwrite(":SOURCE1:PATT:SEL FILENAME, $filename;");
  my $res = $self->iOPC();
}

sub sequenceAdvance {
  my $self = shift;

  $self->iwrite(":SOURCE1:PATT:SEQ:EVENT ONCE;");
  my $res = $self->iOPC();
}

sub sequenceReset {
  my $self = shift;

  $self->iwrite(":SOURCE1:PATT:SEQ:EVENT RESUME;");
  my $res = $self->iOPC();
}

sub startSequencer {
  my $self = shift;

  $self->iwrite(":SOURCE1:PATT:SELECT SEQ;");
  my $res = $self->iOPC();
}

sub EDpolarity {
  my $self = shift;
  my $pol  = shift;    #NORMal | INVerted

  if ( !defined($pol) ) {
    $pol = $self->iquery(":INPUT1:POLARITY?");
    return ($pol);
  } else {
    $self->iwrite( sprintf( ":INPUT1:POLARITY %s;", $pol ) );
    $self->iOPC();
  }
}

sub PGpolarity {
  my $self = shift;
  my $pol  = shift;    #NORMal | INVerted

  if ( !defined($pol) ) {
    $pol = $self->iquery(":OUTPUT1:POLARITY?");
    return ($pol);
  } else {
    $self->iwrite( sprintf( ":OUTPUT1:POLARITY %s;", $pol ) );
    $self->iOPC();
  }
}

#Return BER over last 100ms
sub instantaneousBER {
  my $self = shift;

  my $ret = $self->iquery(":FETCH:SENSE1:ERATION:ALL:FULL:DELTA?");
  return ($ret);
}

#Dump the error message queue ... use "*CLS" to clear it.
sub dumpErrors {
  my $self = shift;

  my @errors = ();
  for ( my $j = 0 ; $j < 20 ; $j++ ) {
    my $stb = $self->ireadstb();
    last if ( !( $stb & $SB{EAV} ) );    #EAV
    my $res = $self->iquery(":SYST:ERR:NEXT?");
    if ( length($res) ) {
      print("$res\n");
      push( @errors, $res );
    } else {
      last;
    }
  }
  return ( \@errors );
}

sub statDump {
  my $self = shift;

  my $reg = $self->ireadstb();
  _dumpBits( $reg, \%SB, "Status Byte" ) if ($reg);

  $reg = $self->iquery("*ESR?");
  _dumpBits( $reg, \%CLSR, "Event Status Register" ) if ($reg);

  $reg = $self->iquery(":STAT:QUES:COND?");
  _dumpBits( $reg, \%QSR, "Questionable Status Register" ) if ($reg);

  $reg = $self->iquery(":STAT:OPER:COND?");
  _dumpBits( $reg, \%OSR, "Operation Status Register" ) if ($reg);

  $reg = $self->iquery(":STAT:PROT:COND?");
  _dumpBits( $reg, \%PSR, "Protection Status Register" ) if ($reg);

  $reg = $self->iquery(":STAT:CLOSS:COND?");
  _dumpBits( $reg, \%CLSR, "Clock Loss Status Register" ) if ($reg);

  $reg = $self->iquery(":STAT:SYMB:COND?");
  _dumpBits( $reg, \%SMSR, "Symbol Status Register" ) if ($reg);
}

sub _dumpBits {
  my $reg    = shift;
  my $fields = shift;
  my $title  = shift;

  my @fnames = ();
  foreach my $bit ( sort( keys(%$fields) ) ) {
    push( @fnames, $bit ) if ( $reg & $fields->{$bit} );
  }
  if ( scalar(@fnames) ) {
    print( $title, ":\n" );
    printf( "%s\n", join( " | ", @fnames ) );
  }
}

__PACKAGE__->meta->make_immutable;
1;

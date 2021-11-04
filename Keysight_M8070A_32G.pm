# -*- mode: perl -*-
package Keysight_M8070A_32G;
use Moose;
use Math::Libm ':all';

#use namespace::autoclean;
use Exception::Class ('UsageError');
## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
## no critic (BitwiseOperators)
#use PDL;
use constant 'OK'  => 0;
use constant 'ERR' => 1;
with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors
has 'ERatioMeasurement' => ( is => 'rw', default => undef );
has 'ERatioAutoClean'   => ( is => 'rw', isa     => 'Bool', default => 1 );
has 'JTOLMeasurement'   => ( is => 'rw', default => undef );
has 'JTOLAutoClean'     => ( is => 'rw', isa     => 'Bool', default => 1 );
my %instrMethods = (
  jitterGlobal       => { scpi => ":SOURCE:JITTer:GLOBAL:STATE 'M1.System'",                    argtype => "BOOLEAN" },
  PJState            => { scpi => ":SOURCE:JITTer:LFRequency:PERiodic:STATE 'M2.DataOut'",      argtype => "BOOLEAN" },
  PJAmplitude        => { scpi => ":SOURce:JITTer:LFRequency:PERiodic:AMPLitude 'M2.DataOut'",  argtype => "NUMBER" },
  PJFrequency        => { scpi => ":SOURce:JITTer:LFRequency:PERiodic:FREQuency 'M2.DataOut'",  argtype => "NUMBER" },
  PJ1State           => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:STATe 'M2.DataOut'",     argtype => "BOOLEAN" },
  PJ1Amplitude       => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:AMPLitude 'M2.DataOut'", argtype => "NUMBER" },
  PJ1Frequency       => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:FREQuency 'M2.DataOut'", argtype => "NUMBER" },
  PJ2State           => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:STATe 'M2.DataOut'",     argtype => "BOOLEAN" },
  PJ2Amplitude       => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:AMPLitude 'M2.DataOut'", argtype => "NUMBER" },
  PJ2Frequency       => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:FREQuency 'M2.DataOut'", argtype => "NUMBER" },
  outputAmpl         => { scpi => ":SOURCE:VOLT:AMPL 'M2.DataOut'",                             argtype => "NUMBER" },
  outputOffset       => { scpi => ":SOURCE:VOLT:OFFSET 'M2.DataOut'",                           argtype => "NUMBER" },
  outputCoupling     => { scpi => ":OUTPUT:COUPLING 'M2.DataOut'", argtype => "ENUM", argcheck => [ 'AC',   'DC' ] },
  outputPolarity     => { scpi => ":OUTPUT:POLARITY 'M2.DataOut'", argtype => "ENUM", argcheck => [ 'NORM', 'INV' ] },
  clockFreq          => { scpi => ":SOURCE:FREQ 'M1.ClkGen'",         argtype => "NUMBER" },
  globalOutputsState => { scpi => ":OUTPUT:GLOBAL:STATE 'M1.System'", argtype => "BOOLEAN" },
  outputState        => { scpi => ":OUTPUT:STATE 'M2.DataOut'",       argtype => "BOOLEAN" },
  deemphasisUnit  => { scpi => ":OUTPUT:DEEMphasis:UNIT 'M2.DataOut'", argtype => "ENUM", argcheck => [ 'DB', 'PCT' ] },
  deemphasisPre2  => { scpi => ":OUTPUT:DEEMphasis:PRECursor2 'M2.DataOut'",  argtype => "NUMBER" },
  deemphasisPre1  => { scpi => ":OUTPUT:DEEMphasis:PRECursor1 'M2.DataOut'",  argtype => "NUMBER" },
  deemphasisPost1 => { scpi => ":OUTPUT:DEEMphasis:POSTCursor1 'M2.DataOut'", argtype => "NUMBER" },
  deemphasisPost2 => { scpi => ":OUTPUT:DEEMphasis:POSTCursor2 'M2.DataOut'", argtype => "NUMBER" },
  deemphasisPost3 => { scpi => ":OUTPUT:DEEMphasis:POSTCursor3 'M2.DataOut'", argtype => "NUMBER" },
  deemphasisPost4 => { scpi => ":OUTPUT:DEEMphasis:POSTCursor4 'M2.DataOut'", argtype => "NUMBER" },
  deemphasisPost5 => { scpi => ":OUTPUT:DEEMphasis:POSTCursor5 'M2.DataOut'", argtype => "NUMBER" },
  outputTransitionTime => {
    scpi     => ":SOURCE:PULSe:TRANsition:FIXed 'M2.DataOut'",
    argtype  => "ENUM",
    argcheck => [ 'SMOOTH', 'MODERATE', 'STEEP', ]
  },
  analyzerClockSource => { scpi => ":Clock:Source 'M2.DataIn'", argtype => "ENUM", argcheck => [ 'SYSclk', 'CLKin' ] },
  alignmentThreshold  => { scpi => ":INPut:ALIGnment:EYE:THReshold 'M2.DataIn'", argtype => "NUMBER" },
);
my $onoffStateGeneric = sub {
  my $self       = shift;
  my $mname      = shift;
  my $on         = shift;
  my $descriptor = $instrMethods{$mname};
  my $subsys     = $descriptor->{scpi};
  if ( !defined($on) ) {
    $subsys =~ s/STATE/STATE?/;
    my $state = $self->iquery($subsys);
    return ($state);
  }
  $on = ( $on != 0 ) ? 1 : 0;
  $self->iwrite( "$subsys," . $on );
};
my $scalarSettingGeneric = sub {
  my $self  = shift;
  my $mname = shift;
  my $val   = shift;
  argCheck( $mname, $val );
  my $descriptor = $instrMethods{$mname};
  my $subsys     = $descriptor->{scpi};
  if ( !defined($val) ) {
    my $val = $self->iquery( queryform($subsys) );
    return ($val);
  }
  $self->iwrite( "$subsys," . $val );
};

sub populateAccessors {
  my $self = shift;
  my $args = shift;
  my $meta = __PACKAGE__->meta;
  $self->logsubsys(__PACKAGE__);
  foreach my $methodName ( keys(%instrMethods) ) {
    my $descriptor = $instrMethods{$methodName};
    if ( $descriptor->{argtype} eq "BOOLEAN" ) {
      $meta->add_method(
        $methodName => sub {
          my $s   = shift;
          my $arg = shift;
          return ( $onoffStateGeneric->( $s, $methodName, $arg ) );
        }
      );
    }
    if ( $descriptor->{argtype} eq "NUMBER" || $descriptor->{argtype} eq "ENUM" ) {
      $meta->add_method(
        $methodName => sub {
          my $s   = shift;
          my $arg = shift;
          $arg = uc($arg) if ( defined($arg) && $descriptor->{argtype} eq "ENUM" );
          return ( $scalarSettingGeneric->( $s, $methodName, $arg ) );
        }
      );
    }
  }
  $meta->make_immutable;
}

sub init {
  my $self = shift;
  $self->populateAccessors();
  $self->iwrite("*RST") if ( $self->{RESET} );    #Get us to default state
  my $err = 'x';                                  # seed for first iteration
                                                  # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /^0/ );                     # error 0 means buffer is empty
  }
  $self->iwrite("*CLS");
  #
  return 0;
}

sub DEMOLISH {
  my $self = shift;
  $self->pluginERATioClean();
  $self->pluginJTOLClean();
}

sub ensureERatio {
  my $self = shift;
  return if ( defined( $self->ERatioMeasurement ) );
  my $measName = sprintf( "ERatio_%llu", time );
  $self->iwrite( sprintf( "PLUGin:ERATio:NEW '%s'", $measName ) );
  $self->ERatioMeasurement($measName);
  return;
}

sub ensureJTOL {
  my $self = shift;
  return if ( defined( $self->JTOLMeasurement ) );
  my $measName = sprintf( "JTOL_%llu", time );
  $self->iwrite( sprintf( "PLUGin:JTOLerance:NEW '%s'", $measName ) );
  $self->JTOLMeasurement($measName);
  return;
}

sub pluginERATioClean {
  my $self         = shift;
  my $measurements = $self->iquery(":PLUGin:ERATio:CATalog?");
  if ( length($measurements) ) {
    foreach my $m ( split( ",", $measurements ) ) {
      $self->iwrite( sprintf( ":PLUGin:ERATio:DELete '%s'", $m ) );
    }
  }
  $self->ERatioMeasurement(undef);
  $self->iOPC(20);
}

sub pluginJTOLClean {
  my $self         = shift;
  my $measurements = $self->iquery(":PLUGin:JTOLerance:CATalog?");
  if ( length($measurements) ) {
    foreach my $m ( split( ",", $measurements ) ) {
      $self->iwrite( sprintf( ":PLUGin:JTOLerance:DELete '%s'", $m ) );
    }
  }
  $self->JTOLMeasurement(undef);
  $self->iOPC(20);
}

sub onoffStateGeneric {
  my $self   = shift;
  my $subsys = shift;
  my $on     = shift;
  if ( !defined($on) ) {
    $subsys =~ s/STATE/STATE?/;
    my $state = $self->iquery($subsys);
    return ($state);
  }
  $on = ( $on != 0 );
  $self->iwrite( "$subsys," . $on );
}

sub scalarSettingGeneric {
  my $self   = shift;
  my $subsys = shift;
  my $val    = shift;
  if ( !defined($val) ) {
    my $val = $self->iquery( queryform($subsys) );
    return ($val);
  }
  $val = ( $val != 0 );
  $self->iwrite( "$subsys," . $val );
}

sub LFSJok {    #(sjfreq, amplitude mUI)
  my $self = shift;
  my $freq = shift;
  my $ampl = shift;
  my $maxJ = $self->maxLFSJ($freq);
  return (0) if ( !defined($maxJ) );
  return ( $ampl <= $maxJ );
}

sub HFSJok {
  my $self = shift;
  my $freq = shift;
  my $ampl = shift;
  my $maxJ = $self->maxHFSJ($freq);
  return (0) if ( !defined($maxJ) );
  return ( ( $ampl <= $maxJ ) ? 1 : 0 );
}

sub maxLFSJ {
  my $self = shift;
  my $freq = shift;
  return (undef) if ( $freq < 100 );
  return (undef) if ( $freq > 5e6 );
  if ( $freq < 1.0e4 ) {
    return (1000.0);
  }
  my $rate = 2.0 * $self->clockFreq();
  my $max  = 1000 * 1.235 * ( $rate / 1e3 ) / $freq;    #mUI
  return ($max);
}

sub maxHFSJ {
  my $self = shift;
  my $freq = shift;
  return (undef) if ( $freq < 1000 );
  return (undef) if ( $freq > 500e6 );
  return (1000.0);                                      #mUI
}

sub maxSJ {
  my $self  = shift;
  my $freq  = shift;
  my $maxLJ = $self->maxLFSJ($freq);
  my $maxHJ = $self->maxHFSJ($freq);
  if ( defined($maxLJ) && defined($maxHJ) ) {
    return ( ( $maxLJ >= $maxHJ ) ? $maxLJ : $maxHJ );
  }
  return ($maxLJ) if ( defined($maxLJ) );
  return ($maxHJ) if ( defined($maxHJ) );
  return (undef);
}

sub simpleSJ {    #(sjfreq, amplitude mUI,  onoff)
  my $self      = shift;
  my $freq      = shift;
  my $amplitude = shift;
  my $onoff     = shift || 1;

  #printf("Set SJ @ %g Hz to %g UI\n",$freq,$amplitude/1000.0);
  #LF PJ 0-1000UI, 100Hz to 10MHz
  #HF PJ 0-1UI, 1kHz to 500MHz
  my $lf = 0;
  if ( $amplitude == 0 && !$onoff ) {
    $self->PJState(0);
    $self->PJ1State(0);
  }
  if ( $freq < 100 || $freq > 500e6 ) {
    UsageError->throw( { err => sprintf( "SJ freq out of range: %g", $freq ) } );
  }
  if ( $self->LFSJok( $freq, $amplitude ) ) {    #We'll use LF PJ
    $lf = 1;
  } elsif ( $self->HFSJok( $freq, $amplitude ) ) {    #Use HF PJ
    $lf = 0;
  } else {
    UsageError->throw( { err => "Bad SJ combination of freq and amplitude" } );
  }
  $self->iwrite(":SOURCE:JITTer:HFRequency:UNIT 'M2.DataOut',UINTerval");
  $self->iwrite(":SOURCE:JITTer:LFRequency:UNIT 'M2.DataOut',UINTerval");
  if ($lf) {
    $self->PJ1State(0);
    $self->PJAmplitude( $amplitude / 1000.0 );
    $self->PJFrequency($freq);
    $self->PJState(1);
  } else {
    $self->PJState(0);
    $self->PJ1Amplitude( $amplitude / 1000.0 );
    $self->PJ1Frequency($freq);
    $self->PJ1State(1);
  }
  $self->iOPC(15);
}

sub txDeemphasis {
  my $self = shift;
  my $taps = shift;    #ref to array
  if ( scalar(@$taps) != 7 ) {
    UsageError->throw( { err => sprintf("txDeemphasis requires argument to be array ref of 7 tap values") } );
  }
  $self->deemphasisPre2( $taps->[0] );
  $self->deemphasisPre1( $taps->[1] );
  $self->deemphasisPost1( $taps->[2] );
  $self->deemphasisPost2( $taps->[3] );
  $self->deemphasisPost3( $taps->[4] );
  $self->deemphasisPost4( $taps->[5] );
  $self->deemphasisPost5( $taps->[6] );
  $self->iOPC(15);
}

sub outputsON {
  my $self = shift;
  my $on   = shift;
  $on = ( $on != 0 );
  $self->outputState($on);
  $self->globalOutputsState($on);
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
  my $res  = $self->iquery(":SOURCE:CONFigure:MINTegration? 'M2.MuxMode'");
  chomp($res);
  chomp($res);
  my ( $a, $b, $c ) = split( ",", $res );
  return ($a);
}

sub setMuxMode {
  my $self    = shift;
  my $mode    = shift;                                                           # "NONe|MUX|DMUX|BOTH"
  my $curmode = $self->iquery(":SOURCE:CONFigure:MINTegration? 'M2.MuxMode'");
  if ( uc($curmode) ne uc($mode) ) {
    $self->iwrite(":SOURCE:CONFigure:MINTegration 'M2.MuxMode',$mode");
  }
  $self->iOPC(45);
}

sub PGbitRate {
  my $self  = shift;
  my $clock = shift;

  #32G mode, PG runs at 1/2 bitrate
  if ( !defined($clock) ) {
    $clock = 2 * $self->clockFreq();
    return ($clock);
  }
  $self->clockFreq( $clock / 2 );
  $self->iOPC(20);
}

sub clockRate {
  my $self  = shift;
  my $clock = shift;
  return ( $self->PGbitRate($clock) );
}
my $prbsXML =
'<sequenceDefinition xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.agilent.com/schemas/M8000/DataSequence">
  <description />
  <sequence>
    <loop>
      <block length="%d">
        <prbs polynomial="%s" />
      </block>
    </loop>
  </sequence>
</sequenceDefinition>
';

sub PGPRBSpattern {
  my $self        = shift;
  my $prbsPattern = shift;
  my $blockLen    = shift || 256;
  my $pattern     = "2^31-1";
  if ( $prbsPattern eq "PRBS7" ) {
    $pattern = "2^7-1";
  } elsif ( $prbsPattern eq "PRBS9" ) {
    $pattern = "2^9-1";
  } elsif ( $prbsPattern eq "PRBS15" ) {
    $pattern = "2^15-1";
  } elsif ( $prbsPattern eq "PRBS23" ) {
    $pattern = "2^23-1";
  }
  my $patt = $self->stringBlockEncode( sprintf( $prbsXML, $blockLen, $pattern ) );

  #$self->iclear();
  #my @errs=$self->getErrors();
  $self->iwrite(":DATA:SEQ:DELALL;");
  $self->iOPC(35);
  $self->iwrite(":DATA:SEQ:DEL 'Generator'");
  $self->iOPC(35);
  $self->iwrite(":DATA:SEQ:NEW 'Generator'");
  $self->iOPC(35);
  $self->iwrite( ":DATA:SEQ:VAL 'Generator'," . $patt );
  $self->iOPC(35);
  $self->iwrite(":DATA:SEQ:BIND 'Generator','M2.DataOut'");
  $self->iwrite(":DATA:SEQ:REST 'Generator'");
  $self->iOPC(35);
}

sub EDPRBSpattern {
  my $self        = shift;
  my $prbsPattern = shift;
  my $blockLen    = shift || 256;
  my $pattern     = "2^31-1";
  if ( $prbsPattern eq "PRBS7" ) {
    $pattern = "2^7-1";
  } elsif ( $prbsPattern eq "PRBS9" ) {
    $pattern = "2^9-1";
  } elsif ( $prbsPattern eq "PRBS15" ) {
    $pattern = "2^15-1";
  } elsif ( $prbsPattern eq "PRBS23" ) {
    $pattern = "2^23-1";
  }
  my $patt = $self->stringBlockEncode( sprintf( $prbsXML, $blockLen, $pattern ) );
  $self->iwrite(":DATA:SEQ:DEL 'Analyzer'");
  $self->iwrite(":DATA:SEQ:NEW 'Analyzer'");
  $self->iOPC(25);
  $self->iwrite(":DATA:SEQ:VAL 'Analyzer',$patt");
  $self->iOPC(25);
  $self->iwrite(":DATA:SEQ:BIND 'Analyzer','M2.DataIn'");
  $self->iwrite(":DATA:SEQ:REST 'Analyzer'");
  $self->iOPC(25);
}

sub prbsSet {
  my $self    = shift;
  my $pattern = shift;    #PRBS7 PRBS9 PRBS15 PRBS23 PRBS31
  $self->PGPRBSpattern($pattern);
  $self->EDPRBSpattern($pattern);
}

sub stringBlockEncode {
  my $self = shift;
  my $str  = shift;
  my $len  = length($str);
  return ( sprintf( "#3%d%s", $len, $str ) );
}

sub errorInsertion {
  my $self    = shift;
  my $errRate = shift;
  if ( $errRate == 0 ) {
    $self->iwrite(":OUTPut:EINSertion:STATe 'M2.DataOut',0");
    return;
  } else {
    $self->iwrite(":OUTPut:EINSertion:MODE 'M2.DataOut',ERATio");
    my $mag = log($errRate) / log(10);
    $mag = floor( abs($mag) + 0.5 ) * ( $mag <=> 0 );
    my $rate = "RM12";
    if ( $mag == -1 ) {
      $rate = "RM1";
    } elsif ( $mag == -2 ) {
      $rate = "RM2";
    } elsif ( $mag == -3 ) {
      $rate = "RM3";
    } elsif ( $mag == -4 ) {
      $rate = "RM4";
    } elsif ( $mag == -5 ) {
      $rate = "RM5";
    } elsif ( $mag == -6 ) {
      $rate = "RM6";
    } elsif ( $mag == -7 ) {
      $rate = "RM7";
    } elsif ( $mag == -8 ) {
      $rate = "RM8";
    } elsif ( $mag == -9 ) {
      $rate = "RM9";
    } elsif ( $mag == -10 ) {
      $rate = "RM10";
    } elsif ( $mag == -11 ) {
      $rate = "RM11";
    }
    $self->iwrite(":OUTPut:EINSertion:RATio 'M2.DataOut',$rate");
    $self->iwrite(":OUTPut:EINSertion:STATe 'M2.DataOut',1");
    $self->iOPC(5);
    return;
  }
}

sub clockLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:CLOSs? 'M2.DataIn'");
  return ( $ret != 0 );
}

sub dataLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:DLOSs? 'M2.DataIn'");
  return ( $ret != 0 );
}

sub syncLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:SLOSs? 'M2.DataIn'");
  return ( $ret != 0 );
}

sub isSynchronized {
  my $self = shift;
  return ( !$self->syncLoss() );
}

sub alignmentLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:SALoss? 'M2.DataIn'");
  return ( $ret != 0 );
}

sub autoAlign {
  my $self = shift;
  my $ret  = $self->iwrite(":INPut:ALIGnment:EYE:AUTO 'M2.DataIn'");
  $self->iOPC(40);
  if ( $self->alignmentLoss ) {
    return (0);
  }
  return (1);
}

sub amplitude {
  my $self = shift;
  my $vpp  = shift;
  $self->outputAmpl($vpp);
}

sub amplitude_cm {
  my $self = shift;
  my $vpp  = shift;
  my $vcm  = shift || 0.0;
  if ( $self->outputCoupling() eq 'DC' ) {
    $self->outputOffset($vcm);
  }
  $self->outputAmpl($vpp);
}

sub trimwhite {
  my $in = shift;
  $in =~ s/^\s+//;
  $in =~ s/\s+$//;
  $in =~ s/\s+/ /;
  return ($in);
}

sub queryform {
  my $in = shift;
  $in = trimwhite($in);
  if ( $in =~ /\s+\'/ ) {    #A subsystem qualifier?
    $in =~ s/\s+\'/? '/;
  } else {
    $in = $in . '?';
  }
  return ($in);
}

sub enumCheck {
  my $var   = shift;
  my $allow = shift;
  return (OK) if ( !defined($var) );
  my %all = map { $_ => 1 } @$allow;
  return (ERR) if ( !exists( $all{ uc($var) } ) );
  return (OK);
}

sub argCheck {
  my $mname = shift;
  my $arg   = shift;
  return (OK) if ( !defined($arg) );
  my $descriptor = $instrMethods{$mname};
  return (OK) if ( !exists( $descriptor->{argcheck} ) );
  if ( $descriptor->{argtype} eq 'ENUM' ) {
    ( OK == enumCheck( $arg, $descriptor->{argcheck} ) )
      || UsageError->throw(
      {
        err => sprintf( "%s requires argument be one of %s", $mname, join( ",", @{ $descriptor->{argcheck} } ) )
      }
      );
  }
  return (OK);
}

sub BERtime {
  my $self   = shift;
  my $period = shift;    #seconds
  my $count  = 100;
  my $res;
  $period = int($period);
  $period = ( $period < 1 ) ? 1 : $period;
  $self->ensureERatio();
  my $meas = $self->ERatioMeasurement;
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:ALOCation '%s','M2.DataIn'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:AEND '%s',FDUR",             $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:DURation '%s',FTIM",         $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:TIME '%s', %g",              $meas, $period ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:RESet '%s'",                             $meas ) );

  while ( $self->syncLoss() && $count ) {
    sleep(0.1);
    $count--;
  }
  return (-1) if ( $self->syncLoss() );
  $self->iwrite( sprintf( ":PLUGin:ERATio:STARt '%s'", $meas ) );
  do {
    sleep(1);
  } while ( $self->iquery( sprintf( ":PLUGin:ERATio:RUN:STATus? '%s", $meas ) ) != 1 );
  $res = $self->iquery( sprintf( ":PLUGin:ERATio:FETCh:DATA? '%s'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:RESet '%s'", $meas ) );
  $res =~ s/[()]//g;
  my @results = split( ",", $res );

  #Array should have Location,Timestamp,ComparedOnes,ComparedZeroes,ErroredOnes,ErroredZeroes
  my $nbits = $results[2] + $results[3];
  my $nerrs = $results[4] + $results[5];
  return ( $nerrs / $nbits );
}

sub simpleJTol {
  my $self      = shift;
  my $fstart    = shift;
  my $fstop     = shift;
  my $points    = shift;
  my $targetBER = shift;
  my $nowait    = shift || 0;
  my $count     = 100;
  $targetBER = 1.0 / $targetBER if ( $targetBER < 1 );
  $self->ensureJTOL();
  my $meas = $self->JTOLMeasurement;

  #  $self->iwrite( sprintf( ":PLUGin:JTOLerance '%s'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:INSTruments:GENerator '%s','M2.DataOut'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:INSTruments:ANALyzer '%s','M2.DataIn'",   $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:TBERatio '%s',%g",            $meas, $targetBER ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:CLEVel '%s',95%",             $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:FRTime '%s',15s",             $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:ARTime '%s',10s",             $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:FREQuency:STARt '%s',%g",     $meas, $fstart ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:FREQuency:STOp '%s',%g",      $meas, $fstop ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:NPOints '%s',%g",             $meas, $points ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:MODE '%s',CHAR",              $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:ALGorithm '%s',DLOGarithmic", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:LOG:SSIZe '%s',10%",          $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:RESet '%s'",                         $meas ) );
  $self->jitterGlobal(1);

  while ( $self->syncLoss() && $count ) {
    sleep(0.1);
    $count--;
  }
  return (-1) if ( $self->syncLoss() );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:STARt '%s'", $meas ) );
  return if ($nowait);
  do {
    sleep(1);
  } while ( $self->iquery( sprintf( ":PLUGin:JTOLerance:RUN:STATus? '%s", $meas ) ) != 1 );
  return;
}

sub getJTOLprogress {
  my $self = shift;
  my $meas = $self->JTOLMeasurement;
  my $prog = $self->iquery( sprintf( ":PLUGin:JTOLerace:RUN:PROGress? '%s'", $meas ) );
  return ($prog);
}

sub getJTOLresults {
  my $self = shift;
  my $meas = $self->JTOLMeasurement;
  my $res  = $self->iquery( sprintf( ":PLUGin:JTOLerance:FETCh:DATA? '%s'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:RESet '%s'", $meas ) );
  $res =~ s/[()]//g;
  my @results = split( ",", $res );

  #@results=Location,( Frequency, Amplitude, NBits, NErrs, BER, PASS/FAIL ) repeated for each freq.
  return ( \@results );
}
1;

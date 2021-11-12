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
with( 'GPIBWrap', 'Throwable', 'CDR' );    #Use Try::Tiny to catch my errors
has 'ERatioMeasurement' => ( is => 'rw', default => undef );
has 'ERatioAutoClean'   => ( is => 'rw', isa     => 'Bool', default => 1 );
has 'JTOLMeasurement'   => ( is => 'rw', default => undef );
has 'JTOLAutoClean'     => ( is => 'rw', isa     => 'Bool', default => 1 );
has 'LocationIn'        => ( is => 'rw', isa     => 'Str',  default => "M2.DataIn" );
has 'LocationOut'       => ( is => 'rw', isa     => 'Str',  default => "M2.DataOut" );
has 'ClockMult'         => ( is => 'rw', isa     => 'Int',  default => 2 );
my $instrumentMethods = {
  jitterGlobal   => { scpi => ":SOURCE:JITTer:GLOBAL:STATE 'M1.System'",                       argtype => "BOOLEAN" },
  PJState        => { scpi => ":SOURCE:JITTer:LFRequency:PERiodic:STATE '!!LocationOut'",      argtype => "BOOLEAN" },
  PJAmplitude    => { scpi => ":SOURce:JITTer:LFRequency:PERiodic:AMPLitude '!!LocationOut'",  argtype => "NUMBER" },
  PJFrequency    => { scpi => ":SOURce:JITTer:LFRequency:PERiodic:FREQuency '!!LocationOut'",  argtype => "NUMBER" },
  PJ1State       => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:STATe '!!LocationOut'",     argtype => "BOOLEAN" },
  PJ1Amplitude   => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:AMPLitude '!!LocationOut'", argtype => "NUMBER" },
  PJ1Frequency   => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:FREQuency '!!LocationOut'", argtype => "NUMBER" },
  PJ2State       => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:STATe '!!LocationOut'",     argtype => "BOOLEAN" },
  PJ2Amplitude   => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:AMPLitude '!!LocationOut'", argtype => "NUMBER" },
  PJ2Frequency   => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:FREQuency '!!LocationOut'", argtype => "NUMBER" },
  outputAmpl     => { scpi => ":SOURCE:VOLT:AMPL '!!LocationOut'",                             argtype => "NUMBER" },
  outputOffset   => { scpi => ":SOURCE:VOLT:OFFSET '!!LocationOut'",                           argtype => "NUMBER" },
  outputCoupling => { scpi => ":OUTPUT:COUPLING '!!LocationOut'", argtype => "ENUM", argcheck => [ 'AC',   'DC' ] },
  outputPolarity => { scpi => ":OUTPUT:POLARITY '!!LocationOut'", argtype => "ENUM", argcheck => [ 'NORM', 'INV' ] },
  clockFreq          => { scpi => ":SOURCE:FREQ 'M1.ClkGen'",         argtype => "NUMBER" },
  globalOutputsState => { scpi => ":OUTPUT:GLOBAL:STATE 'M1.System'", argtype => "BOOLEAN" },
  outputState        => { scpi => ":OUTPUT:STATE '!!LocationOut'",    argtype => "BOOLEAN" },
  deemphasisUnit     =>
    { scpi => ":OUTPUT:DEEMphasis:UNIT '!!LocationOut'", argtype => "ENUM", argcheck => [ 'DB', 'PCT' ] },
  deemphasisPre2       => { scpi => ":OUTPUT:DEEMphasis:PRECursor2 '!!LocationOut'",  argtype => "NUMBER" },
  deemphasisPre1       => { scpi => ":OUTPUT:DEEMphasis:PRECursor1 '!!LocationOut'",  argtype => "NUMBER" },
  deemphasisPost1      => { scpi => ":OUTPUT:DEEMphasis:POSTCursor1 '!!LocationOut'", argtype => "NUMBER" },
  deemphasisPost2      => { scpi => ":OUTPUT:DEEMphasis:POSTCursor2 '!!LocationOut'", argtype => "NUMBER" },
  deemphasisPost3      => { scpi => ":OUTPUT:DEEMphasis:POSTCursor3 '!!LocationOut'", argtype => "NUMBER" },
  deemphasisPost4      => { scpi => ":OUTPUT:DEEMphasis:POSTCursor4 '!!LocationOut'", argtype => "NUMBER" },
  deemphasisPost5      => { scpi => ":OUTPUT:DEEMphasis:POSTCursor5 '!!LocationOut'", argtype => "NUMBER" },
  outputTransitionTime => {
    scpi     => ":SOURCE:PULSe:TRANsition:FIXed '!!LocationOut'",
    argtype  => "ENUM",
    argcheck => [ 'SMOOTH', 'MODERATE', 'STEEP', ]
  },
  analyzerClockSource =>
    { scpi => ":CLOCK:SOURce '!!LocationIn'", argtype => "ENUM", argcheck => [ 'SYS', 'CLK', 'CDR', 'AUXCLK', 'ECR' ] },
  clockTrackSymbolrate => { scpi => ":CLOCK:TRACK:STATe '!!LocationIn'",             argtype => 'BOOLEAN' },
  alignmentThreshold   => { scpi => ":INPut:ALIGnment:EYE:THReshold '!!LocationIn'", argtype => "NUMBER" },
  cdrAuto              => { scpi => ":INPut:CDR:AUTO '!!LocationIn'",                argtype => "BOOLEAN" },
  cdrState             => { scpi => ":INPut:CDR:STATE '!!LocationIn'",               argtype => "BOOLEAN" },
  cdrLoopOrder => { scpi => ":INPut:CDR:LORDer '!!LocationIn'", argtype => "ENUM", argcheck => [ 'FIRST', 'SECOND' ] },
  cdrFirstOrderBandwidth  => { scpi => ":INPut:CDR:FIRSt:LBANdwidth '!!LocationIn'",  argtype => "NUMBER" },
  cdrSecondOrderBandwidth => { scpi => ":INPut:CDR:SECond:LBANdwidth '!!LocationIn'", argtype => "NUMBER" },
  cdrRelock               => { scpi => ":INPut:CDR:RELOck '!!LocationIn'",            argtype => "NONE" },
  cdrOptimize             => { scpi => ":INPut:CDR:OPTimize '!!LocationIn'",          argtype => "NONE" },
};

#Rewrite SCPI commands to direct to correct Module/channel
around 'iwrite' => sub {
  my $orig = shift;
  my $self = shift;
  my $arg  = shift;
  my $lin  = $self->LocationIn;
  my $lout = $self->LocationOut;
  $arg =~ s/!!LocationOut/$lout/g;
  $arg =~ s/!!LocationIn/$lin/g;
  return ( $orig->( $self, $arg ) );
};

sub init {
  my $self = shift;
  $self->instrMethods($instrumentMethods);
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
  $self->cdrInit();
  #
  __PACKAGE__->meta->make_immutable();
  return 0;
}

sub DEMOLISH {
  my $self = shift;
  $self->pluginERATioClean();
  $self->pluginJTOLClean();
}

sub MuxActive {
  my $self = shift;
  my $in   = shift;
  if ( !defined($in) ) {
    return ( $self->ClockMult == 2 );
  }
  if ($in) {
    $self->ClockMult(2);
  } else {
    $self->ClockMult(1);
  }
}

sub ensureERatio {
  my $self = shift;
  return if ( defined( $self->ERatioMeasurement ) );
  my $measName = "ERMeas";
  $self->iwrite( sprintf( "PLUGin:ERATio:NEW '%s'", $measName ) );
  $self->ERatioMeasurement($measName);
  return;
}

sub ensureJTOL {
  my $self = shift;
  return if ( defined( $self->JTOLMeasurement ) );
  my $measName = "JTOLMeas";
  $self->iwrite( sprintf( "PLUGin:JTOLerance:NEW '%s'", $measName ) );
  $self->JTOLMeasurement($measName);
  return;
}

sub pluginERATioClean {
  my $self         = shift;
  my $measurements = $self->iquery(":PLUGin:ERATio:CATalog?");
  if ( length($measurements) ) {
    foreach my $m ( split( ",", $measurements ) ) {
      $m =~ s/"//g;
      $self->iwrite( sprintf( ":PLUGin:ERATio:DELete '%s'", $m ) ) if length($m);
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
      $m =~ s/"//g;
      $self->iwrite( sprintf( ":PLUGin:JTOLerance:DELete '%s'", $m ) ) if length($m);
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
  $self->iwrite(":SOURCE:JITTer:HFRequency:UNIT '!!LocationOut',UINTerval");
  $self->iwrite(":SOURCE:JITTer:LFRequency:UNIT '!!LocationOut',UINTerval");
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
    $clock = $self->ClockMult * $self->clockFreq();
    return ($clock);
  }
  $self->clockFreq( $clock / $self->ClockMult );
  $self->iOPC(20);
}

sub clockRate {
  my $self  = shift;
  my $clock = shift;
  return ( $self->PGbitRate($clock) );
}

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
  $self->iwrite( sprintf( ":DATA:SEQuence:SET '!!LocationOut',PRBS,'%s'", $pattern ) );
  $self->iOPC(35);
}

sub PGClockPattern {
  my $self     = shift;
  my $div      = shift || 2;
  my $blockLen = shift || 256;
  $self->iwrite( sprintf( ":DATA:SEQuence:SET '!!LocationOut',CLOCK,'%d'", $div ) );
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
  $self->iwrite( sprintf( ":DATA:SEQuence:SET '!!LocationIn',PRBS,'%s'", $pattern ) );
  $self->iOPC(35);
}

sub prbsSet {
  my $self    = shift;
  my $pattern = shift;    #PRBS7 PRBS9 PRBS15 PRBS23 PRBS31
  $self->PGPRBSpattern($pattern);
  $self->EDPRBSpattern($pattern);
}

sub errorInsertion {
  my $self    = shift;
  my $errRate = shift;
  if ( $errRate == 0 ) {
    $self->iwrite(":OUTPut:EINSertion:STATe '!!LocationOut',0");
    return;
  } else {
    $self->iwrite(":OUTPut:EINSertion:MODE '!!LocationOut',ERATio");
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
    $self->iwrite(":OUTPut:EINSertion:RATio '!!LocationOut',$rate");
    $self->iwrite(":OUTPut:EINSertion:STATe '!!LocationOut',1");
    $self->iOPC(5);
    return;
  }
}

sub clockLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:CLOSs? '!!LocationIn'");
  return ( $ret != 0 );
}

sub dataLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:DLOSs? '!!LocationIn'");
  return ( $ret != 0 );
}

sub syncLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:SLOSs? '!!LocationIn'");
  return ( $ret != 0 );
}

sub isSynchronized {
  my $self = shift;
  return ( !$self->syncLoss() );
}

sub alignmentLoss {
  my $self = shift;
  my $ret  = $self->iquery(":STATus:INSTrument:SALoss? '!!LocationIn'");
  return ( $ret != 0 );
}

sub autoAlign {
  my $self = shift;
  my $ret;
  $ret = $self->iwrite(":INPut:ALIGnment:EYE:AUTO '!!LocationIn'");
  $self->iOPC(60);
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

sub BERtime {
  my $self   = shift;
  my $period = shift;    #seconds
  my $count  = 100;
  my $res;
  $period = int($period);
  $period = ( $period < 1 ) ? 1 : $period;
  $self->ensureERatio();
  my $meas = $self->ERatioMeasurement;
  $self->iwrite( sprintf( ":PLUGin:ERATio:RESet '%s'",                                $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:ALOCation '%s','!!LocationIn'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:AEND '%s',FDUR",                $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:DURation '%s',FTIM",            $meas ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:TIME '%s', %d",                 $meas, $period ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:INTerval '%s', %d",             $meas, $period ) );
  $self->iwrite( sprintf( ":PLUGin:ERATio:ACQuisition:HISTory '%s', 1",               $meas, ) );

  while ( $self->syncLoss() && $count ) {
    sleep(0.1);
    $count--;
  }
  return (-1) if ( $self->syncLoss() );
  $self->iwrite( sprintf( ":PLUGin:ERATio:STARt '%s'", $meas ) );
  sleep($period);
  my $done = $self->iquery("*OPC?");
  if ( !$done ) {
    sleep( 0.10 * $period );
    $done = $self->iquery("*OPC?");
  }
  if ( !$done ) {
    print("BER measurement didn't complete\n");
    return (-1);
  }
  $res = $self->iquery( sprintf( ":PLUGin:ERATio:FETCh:DATA? '%s'", $meas ) );
  $res =~ s/[()]//g;

  #print "$res\n";
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
  $self->ensureJTOL();
  my $meas = $self->JTOLMeasurement;

  #  $self->iwrite( sprintf( ":PLUGin:JTOLerance '%s'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:INSTruments:GENerator '%s','!!LocationOut'", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:INSTruments:ANALyzer '%s','!!LocationIn'",   $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:RESet '%s'",                                 $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:TBERatio '%s',%g",                    $meas, $targetBER ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:CLEVel '%s',95%%",                    $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:FRTime '%s',1s",                      $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:BSETup:ARTime '%s',1s",                      $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:FREQuency:STARt '%s',%g",             $meas, $fstart ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:FREQuency:STOp '%s',%g",              $meas, $fstop ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:NPOints '%s',%g",                     $meas, $points ) );

  #$self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:CLAuto '%s', 1",                      $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:MODE '%s',CHAR",      $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:ALGorithm '%s',ULOG", $meas ) );
  $self->iwrite( sprintf( ":PLUGin:JTOLerance:MSETup:LOG:SSIZe '%s',30%%", $meas ) );
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
  } while ( $self->iquery( sprintf( ":PLUGin:JTOLerance:RUN:STATus? '%s'", $meas ) ) != 1 );
  return;
}

sub getJTOLprogress {
  my $self = shift;
  my $meas = $self->JTOLMeasurement;
  my $prog = $self->iwrite( sprintf( ":PLUGin:JTOLerance:RUN:PROGress? '%s'", $meas ) );
  $prog = $self->iread();
  $prog += 0.0000001;
  if ( $prog < 1.0 ) {
    my $stat = $self->iquery( sprintf( ":PLUGin:JTOLerance:RUN:STATus? '%s'", $meas ) );
    return (-1) if ( $stat != 1 );
  }
  return ($prog);
}

sub getJTOLresults {
  my $self = shift;
  my $meas = $self->JTOLMeasurement;
  my $res  = $self->iwrite( sprintf( ":PLUGin:JTOLerance:FETCh:DATA:MAXPass? '%s'", $meas ) );
  $res = $self->iread();

  #$self->iwrite( sprintf( ":PLUGin:JTOLerance:RESet '%s'", $meas ) );
  $res =~ s/[()]//g;
  my @results = split( ",", $res );

  #@results=Location,( Frequency, Amplitude, NBits, NErrs, BER, PASS/FAIL ) repeated for each freq.
  return ( \@results );
}
###################################################
# C D R   R o l e
###################################################
sub cdrInit {
  my $self = shift;
}

sub cdrLoopOrder {
  my $self      = shift;
  my $loopOrder = shift;
  my $lorder    = "FIRS";
  if ( $loopOrder == 2 ) {
    $lorder = "SEC";
    $self->loopOrder(2);
  } else {
    $self->loopOrder(1);
  }
  $self->iwrite( sprintf( ":INPut:CDR:LORDer '!!LocationIn', %s", $lorder ) );
}

sub cdrState {
  my $self = shift;
  my $on   = shift;
  if ( $on != 0 ) {
    $self->$self->iwrite(":CLOCK:SOURce '!!LocationIn', CDR");
    $self->iwrite(":INPut:CDR:STATe '!!LocationIn',1");
    $self->iwrite(":INPut:CDR:AUTO '!!LocationIn',1");
    $self->iwrite(":INPut:CDR:OPTimize '!!LocationIn'");
    $self->iOPC(20);
  } else {
    $self->iwrite(":INPut:CDR:STATe '!!LocationIn',0");
    $self->iOPC(20);
  }
}

sub cdrRate {
  my $self = shift;
  my $freq = shift;

  #Nothing to do
}

sub cdrLoopBW {
  my $self    = shift;
  my $bw      = shift;
  my $peaking = shift || 1;    #dB of peaking if second order
  if ( $self->loopOrder == 1 ) {
    $self->iwrite( sprintf( ":INPut:CDR:FIRSt:LBANdwidth '!!LocationIn',%g", $bw ) );
  } else {
    $self->iwrite( sprintf( ":INPut:CDR:SECond:LBANdwidth '!!LocationIn',%g", $bw ) );
    $self->iwrite( sprintf( ":INPut:CDR:SECond:PEAKing '!!LocationIn',%g",    $peaking ) );
  }
}

sub cdrRelock {
  my $self = shift;
  $self->iwrite(":INPut:CDR:RELOck;");
  $self->iOPC(20);
}

sub cdrLocked {
  my $self = shift;
  return ( !$self->clockLoss() );
}
1;

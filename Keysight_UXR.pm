# -*- mode: perl -*-
#
package Keysight_UXR;
use Moose;
use namespace::autoclean;
use Time::HiRes qw(sleep usleep gettimeofday tv_interval);
use Time::Out qw(timeout);
use Carp qw(cluck longmess shortmess);
use Module::Runtime qw(use_module use_package_optimistically);
use Exception::Class ( 'IOError', 'TransportError', 'TimeoutError', 'UsageError' );

## no critic (ProhibitTwoArgOpen)
## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
## no critic (ProhibitNestedSubs)
## no critic (BitwiseOperators)

with( 'GPIBWrap', 'Throwable', 'CDR' );    #Use Try::Tiny to catch my errors

# CDR JTF settings
has 'cdr_loop'         => ( is => 'rw', default => 'SOPLL' );
has 'data_rate'        => ( is => 'rw', default => 9.95328e9 );         #Hz
has 'cdr_bw'           => ( is => 'rw', default => 4e6 );               #Hz
has 'cdr_peaking'      => ( is => 'rw', default => 0.707 );             #dB
has 'cdr_multiplier'   => ( is => 'rw', default => 1.0 );
has 'inputPos'         => ( is => 'rw', default => 1 );
has 'inputNeg'         => ( is => 'rw', default => 2 );
has 'useDiff'          => ( is => 'rw', default => 1 );
has 'specifiedRJ'      => ( is => 'rw', default => sub { undef; } );    #Leave these undef to disable
has 'scopeRJ'          => ( is => 'rw', default => sub { undef; } );
has 'TIEfilterLimits'  => ( is => 'rw', default => sub { undef; } );    #Ref to array of Lower,Upper
has 'TIEfilterShape'   => ( is => 'rw', default => "RECTangular" );
has 'TIEfilterDamping' => ( is => 'rw', default => 0.707 );

my $instrumentMethods = {
  calibrate => { scpi => "*CAL",       argtype => "NONE", queryonly => 1 },
  autoscale => { scpi => ":AUToscale", argtype => "NONE" },
  run       => { scpi => ":RUN",       argtype => "NONE" },
  stop      => { scpi => ":STOP",      argtype => "NONE" },
  single    => { scpi => ":SINGLE",    argtype => "NONE" },
  clear     => { scpi => ":CDISplay",  argtype => "NONE" },
};

my $patterns = {
  PRBS7  => "P7M1",
  PRBS9  => "P9M1",
  PRBS15 => "P15M1"
};

sub init {
  my $self = shift;

  $self->instrMethods($instrumentMethods);
  $self->populateAccessors();

  my @errs = $self->getErrors();

  $self->iwrite(":SYSTEM:HEADER OFF;");
  $self->iwrite(":ACQuire:BANDwidth MAX");
  $self->iwrite( sprintf( ":CHANnel%d:DISPLAY ON", $self->inputPos ) );
  $self->iwrite( sprintf( ":CHANnel%d:DISPLAY ON", $self->inputNeg ) );
  if ( $self->useDiff ) {
    my $pairing = "ADJacent";
    if ( abs( $self->inputPos - $self->inputNeg ) > 1 ) {
      $pairing = "EOTHer";
    }
    $self->iwrite( ":ACQuire:DIFFerential:PARTner " . $pairing );
    $self->iwrite( sprintf( ":CHANnel%d:DIFFerential ON", $self->inputPos ) );
    $self->iwrite( sprintf( ":CHANnel%d:DISPLAY:AUTO 1",  $self->inputPos ) );
  } else {
    $self->iwrite( sprintf( ":CHANnel%d:DIFFerential OFF", $self->inputPos ) );
  }
  $self->cdrInit();
  __PACKAGE__->meta->make_immutable();
}

sub Reset() {
  my $self = shift;

  $self->iwrite(':SYSTem:PRESet DEFault');
  sleep(1);
  return 0;
}

sub ExtReference {
  my $self = shift;
  my $on   = shift;

  if ( $on != 0 ) {
    $self->iwrite(":TIMebase:REFClock 1");
  } else {
    $self->iwrite(":TIMebase:REFClock 0");
  }
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

  #Nothing to do.
}

sub cdrState {
  my $self = shift;
  my $on   = shift;

  #my $loop=$self->cdr_loop;
  $on = $on != 0;

  #if ( "SOPLL" eq $loop ) {
  $self->iwrite(
    sprintf( ":ANALyze:CLOCk:METHod:JTF %s,%g,%g,%g", "SOPLL", $self->data_rate, $self->cdr_bw, $self->cdr_peaking ) );

  #} else {
  #}
}

sub cdrRate {
  my $self = shift;
  my $freq = shift;

  $self->data_rate($freq);
}

sub cdrLoopBW {
  my $self = shift;
  my $bw   = shift;

  $self->cdr_bw($bw);
}

sub cdrRelock {
  my $self = shift;

}

sub cdrLocked {
  my $self = shift;
  return ( $self->iquery(":ANALYZE:CLOCk?") );
}

##########################################################
# Scope helper functions
##########################################################

sub NRZjitterSetup {
  my $self    = shift;
  my $pattern = shift;

  my $chan = $self->inputPos;
  my $patt = $patterns->{$pattern};

  #Calculate number of acq points.
  my $loopTime = 5 / $self->cdr_bw;
  my $srate    = $self->iquery(":ACQUire:SRATE?");
  my $npoints  = 2.10 * $srate * $loopTime;

  if ( !defined($patt) ) {
    UsageError->throw( { error => sprintf( "Unknown pattern: %s.", $patt ) } );
  }

  my $filterLim = $self->TIEfilterLimits;

  $self->iwrite( sprintf( ":ANALyze:SIGNal:TYPE CHANNEL%d,NRZ",                       $chan ) );
  $self->iwrite( sprintf( ":ANALyze:SIGNal:PATTern:PLENgth CHANNEL%d,%s",             $chan, $patt ) );
  $self->iwrite( sprintf( ":DISPLAY:CGRade:SCHeme TEMP;:DISPLAY:CGRade ON,CHANnel%d", $chan ) );
  $self->cdrState(1);
  $self->iwrite( sprintf( ":ACQUIRE:POINTS:ANALOG %g", int($npoints) ) );    #autoscaling will reset this

  $self->iwrite(
    sprintf( ":MEASure:THResholds:METHod CHANnel%d,HYST;:MEASure:THResholds:GENAUTO CHANnel%d", $chan, $chan ) );
  $self->realtimeEye(0);
  $self->iwrite(":MEASure:RJDJ:METHod BOTH");
  $self->iwrite(":MEASure:RJDJ:PLENGth ARBitrary,-2,5");
  $self->iwrite(":MEASure:RJDJ:EDGE BOTH");
  $self->iwrite(":MEASure:RJDJ:UNITs SECond");
  $self->iwrite(":MEASure:RJDJ:BER E12");                                    #measure jitter at 1E-12

  if ( defined($filterLim) && scalar(@$filterLim) == 2 ) {
    $self->iwrite( sprintf( ":MEASure:TIEFilter:SHAPe %s", $self->TIEfilterShape ) );
    $self->iwrite( sprintf( ":MEASure:TIEFilter:STARt %g", $filterLim->[0] ) );
    $self->iwrite( sprintf( ":MEASure:TIEFilter:STOP %g",  $filterLim->[1] ) );
    $self->iwrite(":MEASure:TIEFilter:TYPE BANDpass");
    $self->iwrite(":MEASure:TIEFilter:STATe ON");
  } else {
    $self->iwrite(":MEASure:TIEFilter:STATe OFF");
  }

  if ( defined( $self->scopeRJ ) ) {
    $self->iwrite( sprintf( ":MEASure:RJDJ:SCOPe:RJ ON,%g", $self->scopeRJ ) );
  } else {
    $self->iwrite(":MEASure:RJDJ:SCOPe:RJ AUTO");
  }

  if ( defined( $self->specifiedRJ ) ) {
    $self->iwrite( sprintf( ":MEASure:RJDJ:RJ ON,%g", $self->specifiedRJ ) );
  } else {
    $self->iwrite(":MEASure:RJDJ:RJ OFF");
  }

  $self->iwrite( sprintf( ":MEASure:RJDJ:SOURce CHANnel%d", $chan ) );
}

sub NRZmeasureJitter {
  my $self = shift;

  $self->single();
  $self->clear();
  $self->iwrite(":MEASure:RJDJ:STATe ON");
  my $tstart = time;
  $self->run();
  my $wc = 1;
  while (1) {
    my $jits        = $self->iquery(":MEASURE:RJDJ:TJRJDJ?");
    my @jit_results = split( ",", $jits );

    #printf("%g %g %g\n",$jit_results[2],$jit_results[5],$jit_results[8]);
    last if ( $jit_results[2] < 3 && $jit_results[5] < 3 && $jit_results[8] < 3 );
    sleep(5);
  }
  $self->stop();
  my $runtime = time - $tstart;
  my $hassist = $self->iquery(":MTEST:FOLDing?");
  $wc = $self->iquery(":MTESt:FOLDing:COUNt:WAVEFORMS?") if ($hassist);

  my $jit = $self->iquery(":MEASure:RJDJ:ALL?");
  #print "$jit\n";
  my %results = ();
  my @res     = split( ",", $jit );
  $results{waveforms}        = $wc;
  $results{time}             = $runtime;
  $results{ber}              = $self->iquery(":MEASURE:RJDJ:BER?");
  $results{TIELimits}        = $self->TIEfilterLimits;
  $results{TIEShape}         = $self->TIEfilterShape;
  $results{TIEfilterDamping} = $self->TIEfilterDamping;
  $results{specifiedRJ}      = $self->specifiedRJ;
  $results{scopeRJ}          = $self->scopeRJ;

  for ( my $j = 0 ; $j < scalar(@res) ; $j++ ) {
    my $name = $res[ $j++ ];
    $name =~ s/\(.*\)//;
    $name =~ s/\s+/_/g;
    $results{$name} = $res[ $j++ ];
    $results{ $name . "_state" } = $res[$j];
  }
  return ( \%results );
}

sub realtimeEye {
  my $self = shift;
  my $on   = shift;

  my $chan = $self->inputPos;
  $on = ( $on != 0 );
  my $onoff = $on ? "ON" : "OFF";
  $self->iwrite( sprintf( ":MTEST:FOLDing %s,CHANnel%d", $onoff, $chan ) );    #real-time eye
}

#__PACKAGE__->meta->make_immutable;
1;

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
has 'cdr_loop'       => ( is => 'rw', default => 'SOPLL' );
has 'data_rate'      => ( is => 'rw', default => 9.95328e9 );
has 'cdr_bw'         => ( is => 'rw', default => 4e6 );         #Hz
has 'cdr_peaking'    => ( is => 'rw', default => 2.08 );        #dB
has 'cdr_multiplier' => ( is => 'rw', default => 1.0 );
has 'inputPos'       => ( is => 'rw', default => 1 );
has 'inputNeg'       => ( is => 'rw', default => 2 );
has 'useDiff'        => ( is => 'rw', default => 1 );

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
  my $npoints  = 2 * $srate * $loopTime;

  if ( !defined($patt) ) {
    UsageError->throw( { error => sprintf( "Unknown pattern: %s.", $patt ) } );
  }
  $self->iwrite( sprintf( ":ANALyze:SIGNal:TYPE CHANNEL%d,NRZ",                       $chan ) );
  $self->iwrite( sprintf( ":ANALyze:SIGNal:PATTern:PLENgth CHANNEL%d,%s",             $chan, $patt ) );
  $self->iwrite( sprintf( ":DISPLAY:CGRade:SCHeme TEMP;:DISPLAY:CGRade ON,CHANnel%d", $chan ) );
  $self->cdrState(1);
  $self->iwrite( sprintf( ":ACQUIRE:POINTS:ANALOG %g", int($npoints) ) );    #autoscaling will reset this

  $self->iwrite(
    sprintf( ":MEASure:THResholds:METHod CHANnel%d,HYST;:MEASure:THResholds:GENAUTO CHANnel%d", $chan, $chan ) );
  $self->iwrite( sprintf( ":MTEST:FOLDing ON,CHANnel%d", $chan ) );          #real-time eye
  $self->iwrite(":MEASure:RJDJ:METHod BOTH");
  $self->iwrite(":MEASure:RJDJ:PLENGth ARBitrary,-2,5");
  $self->iwrite(":MEASure:RJDJ:EDGE BOTH");
  $self->iwrite(":MEASure:RJDJ:UNITs SECond");
  $self->iwrite(":MEASure:RJDJ:BER E12");                                    #measure jitter at 1E-12
  $self->iwrite( sprintf( ":MEASure:RJDJ:SOURce CHANnel%d", $chan ) );
}

sub NRZmeasureJitter {
  my $self = shift;

  $self->single();
  $self->clear();
  $self->iwrite(":MEASure:RJDJ:STATe ON");
  my $tstart = time;
  $self->run();
  my $wc;
  while (1) {
    my $jits        = $self->iquery(":MEASURE:RJDJ:TJRJDJ?");
    my @jit_results = split( ",", $jits );
    last if ( $jit_results[2] < 3 && $jit_results[5] < 3 && $jit_results[8] < 3 );
    sleep(5);
  }
  $self->stop();
  my $runtime = time - $tstart;
  $wc = $self->iquery(":MTESt:FOLDing:COUNt:WAVEFORMS?");

  my $jit     = $self->iquery(":MEASure:RJDJ:ALL?");
  my %results = ();
  my @res     = split( ",", $jit );
  $results{waveforms} = $wc;
  $results{time}      = $runtime;
  $results{ber}       = $self->iquery(":MEASURE:RJDJ:BER?");

  my $ix = 1;
  foreach my $name ( "TJ", "RJ", "DJ", "PJ", "BUJ", "DDJ", "DCD", "ISI", "transitions", "scopeRJ", "DDPWS", "ABUJ" ) {
    $results{$name} = @res[ $ix++ ];
    $results{ $name . "_state" } = @res[ $ix++ ];
    $ix++;
  }
  return ( \%results );
}

#__PACKAGE__->meta->make_immutable;
1;

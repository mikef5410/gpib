# -*- mode: perl -*-
package RS_FSWP;
use Moose;
use namespace::autoclean;
use MooseX::MakeImmutable;
use Carp;
use Devel::StackTrace;
use Exception::Class ('UsageError');
## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
## no critic (BitwiseOperators)
#use PDL;
use constant 'OK'  => 0;
use constant 'ERR' => 1;
use constant MODES => {
  PNOise    => "PhaseNoise",
  SMONitor  => "SpectrumMonitor",
  SANalyzer => "Spectrum",
  IQ        => "IQAnalyzer",
  PULse     => "Pulse",
  ADEMod    => "AnalogDemod",
  NOISe     => "Noise",
  SPUR      => "Spur",
  TA        => "TransientAnalysis",
  DDEM      => "VSA"
};
with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors
has 'InstrMode' => ( is => 'rw', default => "PNOise", trigger => \&modeChange );
has 'JitterIntegrationLimits' => ( is => 'rw', default => sub { [ 20e3, 80e6 ] } );

#has 'InstrIOChecked' => ( is => 'rw', default => 0,        trigger => \&instrIOChecking );
my $instrumentMethods = {
  calibrate      => { scpi => "*CAL",                          argtype => "NONE", queryonly => 1 },
  calResult      => { scpi => "CALibration:RESult",            argtype => "NONE", queryonly => 1 },
  displayUpdates => { scpi => ":SYSTem:DISPlay:UPDate",        argtype => "BOOLEAN" },
  trace1State    => { scpi => ":DISPLay:WINDow1:TRACe1:STATe", argtype => "BOOLEAN" },
  trace2State    => { scpi => ":DISPLay:WINDow1:TRACe2:STATe", argtype => "BOOLEAN" },
  trace3State    => { scpi => ":DISPLay:WINDow1:TRACe3:STATe", argtype => "BOOLEAN" },
  trace4State    => { scpi => ":DISPLay:WINDow1:TRACe4:STATe", argtype => "BOOLEAN" },
  trace5State    => { scpi => ":DISPLay:WINDow1:TRACe5:STATe", argtype => "BOOLEAN" },
  trace6State    => { scpi => ":DISPLay:WINDow1:TRACe6:STATe", argtype => "BOOLEAN" },
};

sub init {
  my $self = shift;
  $self->instrMethods($instrumentMethods);
  $self->populateAccessors();
  my @errs = $self->getErrors();
  return 0              if ( $self->{VIRTUAL} );
  $self->iwrite("*RST") if ( $self->{RESET} );     #Get us to default state
  my $err = 'x';                                   # seed for first iteration
                                                   # clear any accumulated errors
                                                   #while ($err) {
                                                   #  $self->iwrite(":SYST:ERR?");
                                                   #  $err = $self->iread( 100, 1000 );
                                                   #  last if ( $err =~ /\+0/ );  # error 0 means buffer is empty
                                                   #}
  $self->displayUpdates(1);                        #A little slower
                                                   #$self->instrErrs();
  $self->iwrite(":SYSTem:ERRor:CLEar:ALL");
  $self->iwrite("*CLS");
  #
  __PACKAGE__->meta->make_immutable();
  return 0;
}

sub DEMOLISH {
  my $self = shift;
}

#Select external 10MHz ref
sub externalReference {
  my $self = shift;
  my $on   = shift;
  $on = ( $on != 0 );
  if ($on) {
    $self->iwrite(":SENSe:ROSCillator:SOURce EXT1");
  } else {
    $self->iwrite(":SENSe:ROSCillator:SOURce INTernal");
  }
}

sub gotoLocal {
  my $self = shift;
  my $on   = shift;
  $on = ( $on != 0 );
  if ($on) {
    $self->iwrite(":SYSTem:KLOCk OFF");
  } else {
    $self->iwrite(":SYSTem:KLOCk ON");
  }
}

# sub instrIOChecking {
#   my $self = shift;
#   MooseX::MakeImmutable->open_up;
#   if ( $self->InstrIOChecked ) {
#     after [qw(iwrite)] => sub {
#       $self->instrErrs();
#     };
#   } else {
#     after [qw(iwrite)] => undef;
#   }
#   MooseX::MakeImmutable->lock_down;
# }
# sub instrErrs {
#   my $self = shift;
#   my $st   = $self->ireadstb();
#   if ( $st & 0x4 ) {
#     my $bt = Devel::StackTrace->new;
#     print STDERR "Last instrument IO had errors.\n";
#     print STDERR $bt->as_string;
#     my $err = 'x';
#     while ($err) {
#       $self->_iwrite(":SYST:ERR?");
#       $err = $self->iread();
#       last if ( $err =~ /^0,/ );    # error 0 means buffer is empty
#       printf( STDERR "$err\n" );
#     }
#   }
# }
sub modeChange {
  my $self    = shift;
  my $newMode = shift;
  my $oldMode = shift;

  return if ( defined($oldMode) && ( $newMode eq $oldMode ) );
  if ( !defined( MODES->{$newMode} ) ) {
    $newMode = "PNOise";
    $self->{InstrMode} = "PNOise";
  }
  $self->iwrite(":INSTrument:SELect $newMode");
  $self->iOPC(20);
}

sub coupleAll {
  my $self = shift;

  if ( $self->{InstrMode} eq 'SANalyzer' ) {
    $self->iwrite(
":INPUT:ATTenuation:AUTO 1;:SENSE:BANDWIDTH:VIDEO:AUTO 1;:SENSE:BANDWIDTH:RESOLUTION:AUTO 1;:SENSE:SWEEP:TIME:AUTO 1;"
    );
  }

  if ( $self->{InstrMode} eq 'PNOise' ) {
    $self->iwrite(":INPUT1:ATTenuation:AUTO ON");

    #$self->iwrite(":BANDWIDTH:VIDEO:AUTO ON");
  }
}

sub JitterSetup {
  my $self = shift;

  $self->modeChange("PNOise");
  $self->iwrite("INIT:CONT OFF");
  $self->iwrite(
    sprintf(
      ":SENSE:FREQ:STARt %g;:SENSE:FREQ:STOP %g",
      $self->JitterIntegrationLimits->[0],
      $self->JitterIntegrationLimits->[1]
    )
  );
  $self->iwrite("INIT:IMMEDIATE");
  $self->coupleAll();
  $self->iwrite(":DISPlay:WINDow1:TRACE1:MODE AVERAGE");
  $self->iwrite(":DISPLay:WINDow1:TRACE2:MODE WRITe");
  $self->trace1State(1);
  $self->trace1State(1);
  $self->trace2State(1);
  $self->trace3State(0);
  $self->trace4State(0);
  $self->trace5State(0);
  $self->trace6State(0);
  $self->iwrite(":SENSE:SWEEP:COUNT 16");    #Average 16 sweeps
  $self->iwrite(":SENSE:SWEEP:XFACTOR 128;:SENSE:SWEEP:XOPTIMIZE 1");
  $self->iwrite(":CALC:RANGE1:EVAL OFF");
  $self->iwrite(
    sprintf(
      ":CALC:RANGE1:EVAL:START %g;:CALC:RANGE1:EVAL:STOP %g",
      $self->JitterIntegrationLimits->[0],
      $self->JitterIntegrationLimits->[1]
    )
  );
  $self->iwrite(":CALC:RANGE1:EVAL:TRACE TRACE1");

  #$self->iwrite(":CALCULATE:RANGE1:EVAL:WEIGHTING 'NONE'");
}

# Return RMS jitter over RANGE1
#
sub JitterMeasure {
  my $self = shift;

  $self->iwrite("INIT:CONT ON");
  $self->iwrite(":SENSE:ADJUST:CONFIGURE:FREQUENCY:AUTOSEARCH 1");
  $self->iOPC(5);
  $self->iwrite("INIT:CONT OFF");
  $self->iwrite("INIT:IMMEDIATE");    #sleep(10);
  $self->iOPC(20);
  my $jitrms = $self->iquery(":FETCH:RANGE1:PNOISE1:RMS?");
  return ($jitrms);
}

#Return Spur dBc amplitudes and jitters in the form:
# (freq,value,freq,value,...) Also return carrier amplitude.
sub SpurList {
  my $self = shift;

  my %res = ();
  $self->iwrite("INIT:CONT ON");
  $self->iwrite(":SENSE:ADJUST:CONFIGURE:FREQUENCY:AUTOSEARCH 1");
  $self->iOPC(5);
  $self->iwrite(":SENSe:SPURs:SORT OFFSet");
  $self->iwrite("INIT:CONT OFF");
  $self->iwrite("INIT:IMMEDIATE");                                     #sleep(10);
  $self->iOPC(20);
  $res{DJrms_wc} = $self->iquery(":FETCh:PNOise2:SPURs:DISCrete?");    #Worst case RMS sum of DJ
  my $spurlist    = $self->iquery(":FETCh:PNOise2:SPURs?");
  my $spurJitlist = $self->iquery(":FETCh:PNOise2:SPURs:Jitter?");
  my @spurs       = split( ",", $spurlist );
  my @jits        = split( ",", $spurJitlist );
  $res{Spurs}        = \@spurs;
  $res{SpurJits}     = \@jits;
  $res{CarrierLevel} = $self->iquery(":SENSe:POWer:RLEVel?");
  return ( \%res );
}

#Return three traces .. ClearWrite, Avg, and XGindicator. Each in the form
# (freq,ampl,freq,ampl...)
sub GetPnoiseTrace {
  my $self = shift;

  my %res = ();
  $self->iwrite("INIT:CONT ON");
  $self->iwrite(":SENSE:ADJUST:CONFIGURE:FREQUENCY:AUTOSEARCH 1");
  $self->iOPC(5);
  $self->iwrite("INIT:CONT OFF");
  $self->iwrite("INIT:IMMEDIATE");    #sleep(10);
  $self->iOPC(20);

  my $points      = $self->iquery(":TRACe1:DATA? TRACE2");
  my $avgPoints   = $self->iquery(":TRACe1:DATA? TRACE1");
  my $xgindicator = $self->iquery(":TRACe1:DATA? XGINdicator");

  my @pts = split( ",", $points );
  $res{Points} = \@pts;
  my @avgPts = split( ",", $avgPoints );
  $res{AvgPoints} = \@avgPts;
  my @indPts = split( ",", $xgindicator );
  $res{XGIndicator} = \@indPts;
  return ( \%res );
}

#__PACKAGE__->meta->make_immutable;
1;

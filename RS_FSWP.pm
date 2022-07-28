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

#has 'InstrIOChecked' => ( is => 'rw', default => 0,        trigger => \&instrIOChecking );
my $instrumentMethods = {
  calibrate      => { scpi => "*CAL",                   argtype => "NONE", queryonly => 1 },
  calResult      => { scpi => "CALibration:RESult",     argtype => "NONE", queryonly => 1 },
  displayUpdates => { scpi => ":SYSTem:DISPlay:UPDate", argtype => "BOOLEAN" },
};

sub init {
  my $self = shift;
  $self->instrMethods($instrumentMethods);
  $self->populateAccessors();
  return 0              if ( $self->{VIRTUAL} );
  $self->iwrite("*RST") if ( $self->{RESET} );     #Get us to default state
  my $err = 'x';               # seed for first iteration
                               # clear any accumulated errors
                               #while ($err) {
                               #  $self->iwrite(":SYST:ERR?");
                               #  $err = $self->iread( 100, 1000 );
                               #  last if ( $err =~ /\+0/ );                     # error 0 means buffer is empty
                               #}
  $self->displayUpdates(1);    #A little slower
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
  return if ( $newMode eq $oldMode );
  if ( !defined( MODES->{$newMode} ) ) {
    $newMode = "PNOise";
    $self->{InstrMode} = "PNOise";
  }
  $self->iwrite(":INSTrument:SELect $newMode");
  $self->iOPC(20);
}

sub coupleAll {
   my $self = shift;

   $self->iwrite(":INPUT:ATTenuation:AUTO 1;:SENSE:BANDWIDTH:VIDEO:AUTO 1;:SENSE:BANDWIDTH:RESOLUTION:AUTO 1;:SENSE:SWEEP:TIME:AUTO 1;");
}

#__PACKAGE__->meta->make_immutable;
1;

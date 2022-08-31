# -*- mode: perl -*-
#
package Keysight_UXR;
use Moose;
use namespace::autoclean;
use Time::HiRes qw(sleep usleep gettimeofday tv_interval);
use Time::Out qw(timeout);
use Carp qw(cluck longmess shortmess);
use Module::Runtime qw(use_module use_package_optimistically);
use Exception::Class ( 'IOError', 'TransportError', 'TimeoutError' );
## no critic (ProhibitTwoArgOpen)
## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
## no critic (ProhibitNestedSubs)
## no critic (BitwiseOperators)
with( 'GPIBWrap', 'Throwable', 'CDR' );    #Use Try::Tiny to catch my errors

# CDR JTF settings
has 'cdr_loop'       => ( is => 'rw', default => 'SOPLL' );
has 'cdr_bw'         => ( is => 'rw', default => 4e6 );       #Hz
has 'cdr_peaking'    => ( is => 'rw', default => 1.0 );       #dB
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
};

sub init {
  my $self = shift;

  $self->instrMethods($instrumentMethods);
  $self->populateAccessors();

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
    $self->iwrite( sprintf( ":CHANnel%d:DISPLAY AUTO",    $self->inputPos ) );
  } else {
    $self->iwrite( sprintf( ":CHANnel%d:DIFFerential OFF", $self->inputPos ) );
  }
  $self->cdrInit();
}

sub Reset() {
  my $self = shift;
  $self->iwrite('*RST');
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
  if ( $on != 0 ) {
    $self->iwrite(":PTIMebase1:RSOurce INTernal;");
    $self->iwrite(":PTIMebase1:RMETHod OLINearity;");
    $self->iwrite(":PTIMebase1:STATe ON;");
    $self->iwrite(":PTIMebase1:RTReference;");
    $self->iwrite(":CRECovery1:SOURce DIFFerential");
    $self->iwrtie(":CRECovery1:LSELect:AUTomatic");
    $self->iOPC(20);
    $self->iwrite(":SYSTem:AUToscale;");
    $self->iOPC(20);
  }
}

sub cdrRate {
  my $self = shift;
  my $freq = shift;
  $self->iwrite(":CRECovery1:CRATe $freq;");
}

sub cdrLoopBW {
  my $self = shift;
  my $bw   = shift;
  $self->iwrite(":CRECovery1:CLBandwidth $bw;");
}

sub cdrRelock {
  my $self = shift;
  $self->iwrite(":CRECovery1:RELock;");
  $self->iOPC(20);
}

sub cdrLocked {
  my $self = shift;
  return ( $self->iquery(":CRECovery1:LOCKed?") );
}
__PACKAGE__->meta->make_immutable;
1;

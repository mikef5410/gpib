# -*- mode: perl -*-
package Agilent_ESA;
use Moose;
use InstrumentTrace::SA;
use PDL::Core;

use namespace::autoclean;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

sub init {
  my $self = shift;

  return 0 if ( $self->{VIRTUAL} );

  $self->iconnect();
  $self->iwrite("*RST;") if ( $self->{RESET} );    #Get us to default state

  my $err = 'x';                                   # seed for first iteration
                                                   # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /\+0/ );                     # error 0 means buffer is empty
  }
  $self->iwrite("*CLS;");
  #
  return 0;

}

sub SetupSA {
  my ($self) = shift;

  my ($fa) = shift;                                # start frequency hertz
  my ($fb) = shift;                                # stop frequency hertz
  my ($rl) = shift;                                # reference level dbm
  my ($au) = shift;                                # absolute amplitude units string
  my ($rb) = shift;                                # resolution bandwidth hertz
  my ($vb) = shift;                                # video bandwidth hertz
  my ($st) = shift;                                # sweep time seconds
  my ($lg) = shift;                                # linear (if==0) or dB per div (if>0)

  my $sweeptime;
  if ( $lg < 0 ) {
    Carp("You've asked for negative dB per division.");
    return ();
  }

  my $fr = $self->{FreqRef};                       # 10MHz ref

  #$self->iwrite("FREF $fr;");	    # EXT or INT

  $self->iwrite(":FREQuency:STARt $fa");
  $self->iwrite(":FREQuency:STOP $fb");

  $self->iwrite(":UNIT:POWer $au");
  $self->iwrite(":DISPlay:WINDow:TRACe:Y:SCALe:RLEVel $rl");

  if ( 'auto' eq lc($rb) ) {
    $self->iwrite(':SENSe:BANDwidth:RESolution:AUTO ON');
  } else {
    $self->iwrite(":SENSe:BANDwidth:RESolution $rb");
  }

  if ( 'auto' eq lc($vb) ) {
    $self->iwrite(':SENSe:BANDwidth:VIDeo:AUTO ON');
  } else {
    $self->iwrite(":SENSe:BANDwidth:VIDeo $vb");
  }

  if ( 'auto' eq lc($st) ) {
    $self->iwrite(':SENse:SWEep:TIME:AUTO ON');
  } else {
    $self->iwrite(":SENse:SWEep:TIME $st");
  }

  $self->iwrite(':DISPlay:WINDow:TRACe:Y:SCALe:SPACing LINear') if ( $lg == 0 );
  if ( $lg > 0 ) {
    $self->iwrite(':DISPlay:WINDow:TRACe:Y:SCALe:SPACing LOGarithmic');
    $self->iwrite(":DISPlay:WINDow:TRACe:Y:SCALe:PDIVision $lg");
  }

  # The following state attributes are issued to insure that Setup creates
  # a known state. It may be necessary to add more as time goes on...
  $self->iwrite(':TRACe1:MODE WRITe');          # No max hold
  $self->iwrite(':SENSe:AVERage:STATe OFF');    # No averaging

  $self->iOPC();

  if ( $st eq 'auto' ) {                        # need to determine the actual sweep time
                                                # video averaging is not supported in this code
                                                # no obvious way to determine if it is on or off!
                                                # so turn it off...
    $self->iwrite(':SENse:SWEep:TIME?');
    $sweeptime = $self->iread();                # Read INSTR response & Store
    chomp($sweeptime);                          # Remove trailing newline

  } else {
    $sweeptime = $st;                           # use the time provided
  }

  #hold( "at end of setupsa" );
  return 0;
}

#Suck down an entire trace from an SA
sub getTRA {
  my $self = shift;

  my $traceDump = InstrumentTrace::SA->new();

  $self->iwrite(":FREQ:START?");
  $traceDump->FA( $self->iread() + 0.0 );

  $self->iwrite(":FREQ:STOP?");
  $traceDump->FB( $self->iread() + 0.0 );

  $self->iwrite(":DISP:WIND:TRACE:Y:RLEV?");
  $traceDump->RL( $self->iread() + 0.0 );

  $self->iwrite(":BWID:RES?");
  $traceDump->RB( $self->iread() + 0.0 );

  $self->iwrite(":BWID:VID?");
  $traceDump->VB( $self->iread() + 0.0 );

  $self->iwrite(":SWEEP:TIME?");
  $traceDump->ST( $self->iread() + 0.0 );

  $self->iwrite(":DISP:WIND:TRACE:Y:PDIVision?");
  $traceDump->LG( $self->iread() + 0.0 );

  $self->iwrite(":UNIT:POWER?");
  my $res = $self->iread();
  chomp($res);
  $traceDump->AUNITS($res);

  $self->iwrite(":FORMAT:TRACE:DATA ASCII;");
  $self->iwrite(":TRACE:DATA? TRACE1");
  my $rdg = $self->iread();
  chomp($rdg);
  my @rdg = split( ",", $rdg );
  map { $_ + 0.0 } @rdg;
  $traceDump->TDATA( pdl(@rdg) );

  $traceDump->TSIZE( scalar(@rdg) );

  return ($traceDump);
}

__PACKAGE__->meta->make_immutable;
1;

# -*- mode: perl -*-
#perltidy -i=2 -ce

package Measurement::ReceiverSensitivity;
use Moose;
use namespace::autoclean;
use Agilent_N4903A;
use PDL;
use PDL::NiceSlice;
use Time::HiRes qw(sleep usleep);
use Try::Tiny;

with 'MooseX::Log::Log4perl';

has 'jbert'          => ( is => 'rw' );
has 'ps'             => ( is => 'rw' );
has 'bitrate'        => ( is => 'rw' );
has 'subrateDivider' => ( is => 'rw' );
has 'pattern'        => ( is => 'rw' );
has 'attenuation'    => ( is => 'rw' );
has 'withBiasTee'    => ( is => 'rw' );

has 'amplitudeSetter' => ( is => 'rw' );
has 'vcmSetter'       => ( is => 'rw' );

#
# Measure Rx sentitivity by stepping amplitude downward
# taking note of BER. Interpolate/Extrapolate to  1E-3, 1E-4, and 1E-12
# amplitudes.
# Vcm is set separately and not touched here.
sub measureSensitivity {
  my $self = shift;

  my $ampl = 0;
  my $in;
  my $jbert = $self->jbert();

  $jbert->amplitude_cm( 0.7, $jVoffs );

  print("Find sync threshold... ") if ($verbose);
  my $inc = 70;
  for ( $ampl = 700 ; $ampl >= 10 ; $ampl -= $inc ) {
    $inc = int( 0.5 + ( $ampl / 10 ) );
    $jbert->amplitude_cm( $ampl / 1000, $jVoffs );
    last if ( !$jbert->isSynchronized() );
  }
  print("$ampl mV\n") if ($verbose);

  my $bertime = 5;
  $inc = ( $ampl / 10 > 20 ) ? 20 : $ampl / 10;
  $inc = int( $inc + 0.5 );
  my $swpmax  = $ampl * 4;
  my @ampls   = ();
  my @berlist = ();

  $swpmax = ( $swpmax / 1000 > 3.0 - $jVoffs ) ? ( 3.0 - $jVoffs ) * 1000 : $swpmax;
  for ( $a = $ampl + $inc ; $a < $swpmax ; $a += $inc ) {
    $jbert->amplitude_cm( $a / 1000, $jVoffs );
    my $ber = $jbert->BERtime($bertime);
    print("$a $bertime $ber\n") if ($verbose);
    next                        if ( $ber < 0 );    #No sync
    if ( $ber == 0 ) {                              #No errors
      $bertime *= 2;
      last if ( $bertime >= $maxTime );
      $a -= $inc;
      next;
    } else {
      if ( $ber > 0 ) {
        push( @ampls,   $a );
        push( @berlist, $ber );
      }
    }
    last if ( $ber < 1E-10 && $ber >= 0 );
    $inc = int( 0.5 + $a / 10 );                    #Take larger steps as amplitude gets larger
  }
  my $bers       = pdl(@berlist);
  my $amplitudes = pdl(@ampls);

  #print($bers,"\n");
  #print($amplitudes,"\n");

  my ( $iampl, $err );
  try {
    ( $iampl, $err ) = PDL::Primitive::interpolate( pdl( 1e-3, 1e-4, 1e-12 ), $bers, $amplitudes );
  } catch {
    print("Interpolation error at $vcm V.\n");
    print $amplitudes, "\n";
    print $bers,       "\n";
    $iampl = pdl( 0, 0, 0 );
  };

  my $ampcor = 10.0**( -1.0 * $atten / 20.0 );
  $iampl = 2 * $iampl * $ampcor;
  printf( "Amplitude\@1E-3:  %g mV\n", $iampl->at(0) ) if ($verbose);
  printf( "Amplitude\@1E-4:  %g mV\n", $iampl->at(1) ) if ($verbose);
  printf( "Amplitude\@1E-12: %g mV\n", $iampl->at(2) ) if ($verbose);
  return ($iampl);
}

#Calculate what to set the source amplitude to to get a
#value at the DUT. SINGLE-ENDED amplitudes!
sub sourceAmpl {
  my $self = shift;
  my $ampl = shift;

  my $atten  = $self->attenuation();
  my $ampcor = 10**( -1.0 * $atten / 20 );
  my $src    = $ampl / $ampcor;
  return ($src);
}

__PACKAGE__->meta->make_immutable;
1;

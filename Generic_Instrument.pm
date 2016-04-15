# -*- mode: perl -*-
package Generic_Instrument;
use Moose;
use namespace::autoclean;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

sub init {
  my $self      = shift;

  return 0      if ( $self->{VIRTUAL} );

  $self->iconnect();
  $self->iwrite("*RST;") if ($self->{RESET}); #Get us to default state

  my $err = 'x';    # seed for first iteration
  # clear any accumulated errors
  while( $err ) {
    $self->iwrite(":SYST:ERR?");
    $err    = $self->iread( 100, 1000 );
    last if ($err =~/\+0/);         # error 0 means buffer is empty
  }
  $self->iwrite("*CLS;");
  #
  return 0;

}



__PACKAGE__->meta->make_immutable;
1;

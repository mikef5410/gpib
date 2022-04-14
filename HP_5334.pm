# -*- mode: perl -*-
package HP_5334;
use Moose;
use namespace::autoclean;

#The HP5334 doesn't assert EOI on last byte, so we need to set the
#term char to "\n", and use that on reads.
with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

sub BUILDARGS {
  my $self = shift;
  my @args = @_;
  my %args = (@args);
  $args{termChr} = 0x0a;
  return \%args;
}

sub init {
  my $self = shift;
  return 0            if ( $self->{VIRTUAL} );
  $self->iwrite("IN") if ( $self->{RESET} );     #Get us to default state
  my $err = 'x';                                 # seed for first iteration
                                                 # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /\+0/ );                   # error 0 means buffer is empty
  }
  $self->iwrite("*CLS");
  #
  return 0;
}

sub iread {
  my $self = shift;
  return if ( !defined($self) );
  if ( !defined( $self->gpib ) ) {
    $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iread") );
    return ("");
  }
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      ( $self->{bytes_read}, my $in, $self->{reason} ) =
        $self->gpib()->vxi_read( @_, termchrset => 1, termchr => "\n" );
      $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iread -> %s", $in ) );
      return ($in);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      my $len = shift(@_);
      my $tmo = shift(@_);
      my $in  = $self->gpib()->iread( $len, $tmo, 0x80 );
      chomp($in);
      chomp($in);
      $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iread -> %s", $in ) );
      return ($in);
      last(SWITCH);
    }
    TransportError->throw( { error => 'Unknown GPIB transport' } );
  }
}

sub id {
  my $self = shift;
  return if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("id") );
  return if ( !defined( $self->gpib ) );
  return ( $self->iquery("ID") );
}
__PACKAGE__->meta->make_immutable;
1;

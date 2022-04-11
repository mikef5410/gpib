# -*- mode: perl -*-
package HP3478A;
use Moose;
use namespace::autoclean;
with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

sub init {
  my $self = shift;
  return 0            if ( $self->{VIRTUAL} );
  $self->iwrite("H0") if ( $self->{RESET} );     #Get us to default state
  my $err = $self->errRead();                    #Get the error byte as two octal numbers. Clear on read
                                                 # clear any accumulated error
  $self->iclear();
  #
  return 0;
}

sub measureDCV {
  my $self = shift;
  return ( $self->iquery("H1") );
}

sub measureACV {
  my $self = shift;
  return ( $self->iquery("H2") );
}

sub measureRes {
  my $self = shift;
  return ( $self->iquery("H3") );
}

sub measure4Res {
  my $self = shift;
  return ( $self->iquery("H4") );
}

sub measureDCI {
  my $self = shift;
  return ( $self->iquery("H5") );
}

sub measureACI {
  my $self = shift;
  return ( $self->iquery("H6") );
}

sub initiate {
  my $self = shift;
  $self->iwrite("T1");
}

sub displayNormal {
  my $self = shift;
  $self->iwrite("D1");
}

sub displayText {
  my $self = shift;
  my $text = shift;
  $self->iwrite( "D2" . substr( $text, 0, 12 ) . "\n" );
}

#Makes readings over bus much faster...
sub displayFreeze {
  my $self = shift;
  my $text = shift;
  $self->iwrite( "D3" . substr( $text, 0, 12 ) . "\n" );
}

# Error byte bitmask:
#  0x1 = CAL RAM bad checksum
#  0x2 = RAM bad
#  0x4 = ROM bad
#  0x8 = A/D slope error
#  0x10 = A/D internal self test error
#  0x20 = A/D link error
#  0x40 = always 0
#  0x80 = always 0
sub errRead {
  my $self = shift;
  my $res  = octal( $self->iquery('E') );
  return ($res);
}
__PACKAGE__->meta->make_immutable;
1;

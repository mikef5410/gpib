# -*- mode: perl -*-
#
package GPIBWrap;

#use Moose;
#use namespace::autoclean;
use Moose::Role;
use Time::HiRes qw(sleep usleep);

with 'Throwable';    #Use Try::Tiny to catch my errors

has 'gpib'       => ( is => 'rw', required => 1 );
has 'bytes_read' => ( is => 'ro', default  => 0 );
has 'reason'     => ( is => 'ro', default  => 0 );

# This class wraps a variety of underlying GPIB mechanisms into a
# common API

sub ilock() {
  my $self = shift;
  my $wait = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      if ($wait) {
        $self->gpib()->vxi_lock( [ waitforlock => 'true' ] );
      } else {
        $self->gpib()->vxi_lock();
      }
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iwrite($) {
  my $self = shift;
  my $arg  = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

  chomp($arg);
  chomp($arg);
  $arg .= "\n";
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_write($arg);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iread() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      ( $self->{bytes_read}, my $in, $self->{reason} ) =
        $self->gpib()->vxi_read();
      return ($in);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iquery() {
  my $self = shift;
  my $arg  = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

  $self->iwrite($arg);
  return ( $self->iread() );
}

sub iOPC() {
  my $self    = shift;
  my $timeout = shift;    #seconds (fractional ok)
  my $ret;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

  $self->iwrite("*OPC;");

  #Poll STB for operation complete until timeout
  if ( defined($timeout) ) {
    while ( $timeout > 0 ) {
      $ret = $self->iquery("*ESR?") || 0;
      if ( $ret & (0x1) ) {
        return (1);
      }
      usleep( ( $timeout > 1.0 ) ? 1e6 : $timeout * 1e6 );
      $timeout = $timeout - 1.0;
    }
    return (-1);
  }

  while (1) {
    $ret = $self->iquery("*ESR?") || 0;
    if ( $ret & (0x1) ) {
      return (1);
    }

    #$ret = $self->iquery("*OPC?") || 0;
    #last if ( $self->reason() != 0 );
    #sleep(1);
  }
  return ( $ret & 0x1 );
}

sub id() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
  return ( $self->iquery("*IDN?") );
}

sub icreate_intr_chan() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_create_intr_chan();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub ireadstb() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      return ( ( $self->gpib()->vxi_readstatusbyte() )[1] );
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub ienablesrq($) {
  my $self   = shift;
  my $handle = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_enable_srq($handle);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iwai() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_wait_for_interrupt();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub idestroy_intr_chan() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_destroy_intr_chan();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iabort() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_abort();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iclear() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_clear();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub itrigger() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_trigger();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub ilocal() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_local();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iremote() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_remote();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iunlock() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_unlock();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

sub iclose() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_close();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    $self->throw( { err => 'Unknown GPIB transport' } );
  }
}

1;

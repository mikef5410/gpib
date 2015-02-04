# -*- mode: perl -*-
#
package GPIBWrap;

#use Moose;
#use namespace::autoclean;
use Moose::Role;

with 'Throwable';    #Use Try::Tiny to catch my errors

has 'gpib'       => ( is => 'rw', required => 1 );
has 'bytes_read' => ( is => 'ro', default  => 0 );
has 'reason'     => ( is => 'ro', default  => 0 );

# This class wraps a variety of underlying GPIB mechanisms into a
# common API

sub ilock() {
  my $self = shift;
  my $wait = shift;

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

  $self->iwrite($arg);
  return ( $self->iread() );
}

sub iOPC() {
  my $self = shift;
  return ( $self->iquery("*OPC?") );
}

sub id() {
  my $self = shift;
  return ( $self->iquery("*IDN?") );
}

sub icreate_intr_chan() {
  my $self = shift;

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

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      return ( $self->gpib()->vxi_readstatusbyte() );
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

sub ilocal() {
  my $self = shift;

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

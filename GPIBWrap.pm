# -*- mode: perl -*-
#
package GPIBWrap;

#use Moose;
#use namespace::autoclean;
use Moose::Role;
use Time::HiRes qw(sleep usleep);
use Carp;

with 'Throwable';    #Use Try::Tiny to catch my errors
with 'MooseX::Log::Log4perl';

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf( "ilock %s", $wait ) );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf( "iwrite %s", $arg ) );

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
      $self->log('GPIBWrap.IOTrace')->info( sprintf( "iread -> %s", $in ) );
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
  $self->log('GPIBWrap.IOTrace')->info( sprintf( "iquery %s", $arg ) );

  $self->iwrite($arg);
  return ( $self->iread() );
}

sub iOPC() {
  my $self    = shift;
  my $timeout = shift;    #seconds (fractional ok)
  my $ret;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
  $self->log('GPIBWrap.IOTrace')->info( sprintf( "iOPC %g", $timeout ) );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("id") );
  return ( $self->iquery("*IDN?") );
}

sub icreate_intr_chan() {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
  $self->log('GPIBWrap.IOTrace')->info( sprintf("icreate_intr_chan") );

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
  my $rval = 0;

SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $rval = ( $self->gpib()->vxi_readstatusbyte() )[1];
      $self->log('GPIBWrap.IOTrace')->info( sprintf( "ireadstb -> 0x%x", $rval ) );
      return ($rval);
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
  $self->log('GPIBWrap.IOTrace')->info( sprintf( "ienablesrq %s", $handle ) );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("iwai") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("idestroy_intr_chan") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("iabort") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("iclear") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("itrigger") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("ilocal") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("iremote") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("iunlock") );

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
  $self->log('GPIBWrap.IOTrace')->info( sprintf("iclose") );

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

sub isQuery {
  my $self = shift;
  my $str  = shift;

  chomp($str);
  chomp($str);
  if ( $str =~ /\?;?\s*$/ ) {
    return (1);
  } else {
    return (0);
  }
}

sub getErrors {
  my $self = shift;

  my @errlist = ();
  my $res     = "";
  while (1) {
    $res = $self->iquery(":SYSTem:ERRor:NEXT?");
    chomp($res);
    last if ( $res =~ /0,/ );
    push( @errlist, $res );
  }
  return ( \@errlist );
}

1;

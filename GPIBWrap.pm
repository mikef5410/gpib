# -*- mode: perl -*-
# perltidy -i=2 -ce -l=100

package GPIBWrap;

#use Moose;
#use namespace::autoclean;
use Moose::Role;
use Time::HiRes qw(sleep usleep);
use Carp;

## no critic (BitwiseOperators)

with 'Throwable';    #Use Try::Tiny to catch my errors
with 'MooseX::Log::Log4perl';

has 'gpib'       => ( is => 'rw', required => 1 );
has 'bytes_read' => ( is => 'ro', default  => 0 );
has 'reason'     => ( is => 'ro', default  => 0 );

# This class wraps a variety of underlying GPIB mechanisms into a
# common API

=head1 NAME

GPIBWrap - A Moose Role to abstract GPIB access across multiple providers

=head1 VERSION

VERSION 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

  package Some_Instrument;
  use Moose;
  use namespace::autoclean;

  with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors


=head2 DESCRIPTION

This Moose role attempts to provide a common API to VXI11::Client and RPCINST. It's your choice which to use.
Instruments are Moose objects that inherit from this role.


=head2 LOGGING

Logging is implemented with the Moose role MooseX::Log::Log4perl
Initialize Log4perl with:

  use Log::Log4perl qw(:easy);
  Log::Log4perl->easy_init($ERROR);    #Normally quiet logging.

Trace logging is implermented on the channel 'GPIBWrap.IOTrace' at level "info".
Turn it on with:
C<Log::Log4perl-E<gt>get_logger("GPIBWrap.IOTrace")-E<gt>level($INFO);>

=head2 Object Attributes

=over 4

=item *

B<gpib> - The underlying GPIB interface object for this device

=item *

B<bytes_read> - The number of bytes read in the last read operation

=item *

B<reason> - Reason the read terminated


=back

=head2 METHODS

=over 4

=item B<< $instrument->ilock([$wait]) >>

Get an exclusive lock on the instrument. If $wait is true, wait for the lock.

=back

=cut

sub ilock {
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

=over 4

=item B<< $instrument->iwrite($arg) >>

Send a string ($arg) to the instrument.

=back

=cut

sub iwrite {
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

=over 4

=item B<< $instrument->iread() >>

Read a response from the instrument.

=back

=cut

sub iread {
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

=over 4

=item B<< $instrument->iquery($arg) >>

Just an iwrite($arg) followed by an iread().

=back

=cut

sub iquery {
  my $self = shift;
  my $arg  = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
  $self->log('GPIBWrap.IOTrace')->info( sprintf( "iquery %s", $arg ) );

  $self->iwrite($arg);
  return ( $self->iread() );
}

=over 4

=item B<< $instrument->iOPC([$timeout]) >>

Very similar to *OPC?, however, if the timeout is specified (in seconds, fractions are ok),
it'll return -1 if the timeout expires. Returns 1 when the operation in complete. This is a better
way to wait for long operations than *OPC? because lan devices can timeout an the instrument doesn't know it.
This code will poll every second for the Operation Complete bit in the ESR, thus avoiding timeouts on the lan.

=back

=cut

sub iOPC {
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

=over 4

=item B<< $instrument->id() >>

Shorthand for $instrument->iquery("*IDN?");

=back

=cut

sub id {
  my $self = shift;

  return if ( !defined($self) );
  return if ( !defined( $self->gpib ) );
  $self->log('GPIBWrap.IOTrace')->info( sprintf("id") );
  return ( $self->iquery("*IDN?") );
}

=over 4

=item B<< $instrument->icreate_intr_chan() >>

Makes a "thread" to watch for interrupts from the instrument, for, say, SRQ's

=back

=cut

sub icreate_intr_chan {
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

=over 4

=item B<< $instrument->ireadstb() >>

Out of band reads of the instrument's status byte.

=back

=cut

sub ireadstb {
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

=over 4

=item B<< $instrument->ienablesrq($handle) >>

Enable SRQ, and call $handle when it happens.

=back

=cut

sub ienablesrq {
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

=over 4

=item B<< $instrument->iwai() >>

Wait for interrupt.

=back

=cut

sub iwai {
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

=over 4

=item B<< $instrument->idestroy_intr_chan() >>

Kill the "thread" that watches for lan interrupts.

=back

=cut

sub idestroy_intr_chan {
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

=over 4

=item B<< $instrument->iabort() >>

Abort the current operation.

=back

=cut

sub iabort {
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

=over 4

=item B<< $instrument->iclear() >>

Effect a Selected Device Clear

=back

=cut

sub iclear {
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

=over 4

=item B<< $instrument->itrigger() >>

Send a bus trigger.

=back

=cut

sub itrigger {
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

=over 4

=item B<< $instrument->ilocal() >>

Cause the instrument to go to local control.

=back

=cut

sub ilocal {
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

=over 4

=item B<< $instrument->iremote() >>

Put the instrument in remote control (local lockout).

=back

=cut

sub iremote {
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

=over 4

=item B<< $instrument->iunlock() >>

Give up your lock on the device.

=back

=cut

sub iunlock {
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

=over 4

=item B<< $instrument->iclose() >>

Close this connection.

=back

=cut

sub iclose {
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

=over 4

=item B<< $instrument->isquery($arg) >>

Attempts to decide whether this string is a query. Assumes SCPI. If your instrument isn't 
SCPI, you can override this method.

=back

=cut

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

=over 4

=item B<< $instrument->getErrors() >>

Reads the instrument Error Queue (emptying it in the process). Returns a 
reference to a list of the errors in the form  '100, "Some error message"' (or as the instrument responds
to the query).  If there are no errors a reference to an empty list is returned.

This method assumes SCPI, and :SYSTem:ERRor:NEXT? is defined. If it doesn't you can override this
method.

=back

=cut

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

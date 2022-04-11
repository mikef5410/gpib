# -*- mode: perl -*-
# perltidy -i=2 -ce -l=100
package GPIBWrap;

#use Moose;
#use namespace::autoclean;
use Moose::Role;
use Time::HiRes qw(sleep usleep gettimeofday tv_interval);
use Time::Out qw(timeout);
use Carp qw(cluck longmess shortmess);
use Module::Runtime qw(use_module use_package_optimistically);
use Exception::Class ( 'IOError', 'TransportError', 'TimeoutError', 'UsageError' );
use Net::Telnet;    #For e2050Reset only
use Log::Log4perl;
use constant 'TERM_MAXCNT'      => 1;
use constant 'TERM_CHR'         => 2;
use constant 'TERM_END'         => 4;
use constant 'TERM_NON_BLOCKED' => 8;
use constant 'OK'               => 0;
use constant 'ERR'              => 1;
## no critic (BitwiseOperators)
## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
with 'Throwable';    #Use Try::Tiny to catch my errors
with 'MooseX::Log::Log4perl';
has 'gpib'           => ( is => 'rw', default => undef );
has 'bytes_read'     => ( is => 'ro', default => 0 );
has 'reason'         => ( is => 'ro', default => 0 );
has 'connectString'  => ( is => 'rw', default => '' );
has 'defaultTimeout' => ( is => 'rw', default => 0 );
has 'host'           => ( is => 'rw', default => '' );
has 'logsubsys'      => ( is => 'rw', default => __PACKAGE__ );
has 'instrMethods'   => ( is => 'rw', isa     => 'HashRef', default => sub { {} } );

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
Instruments are Moose objects that inherit from this role. The simplest way to use this role is to do the 
connection initialization via the C<connectString> construction arg, as in:

  my $instrument = Some_Instrument->new(connectString=>"VXI11::10.1.2.3::inst0"); 
  my $inst2  = Some_Instrument->new(connectString=>"VXI11::langpib.example.com::hpib,12");
  my $inst3  = Some_Instrument->new(connectString=>"SICL::langpib2.example.com::hpib,18");

However, you can make your own interface and hand it to this role, as in:

  my $iface = VXI11::Client->new(address=>"1.2.3.4", device=>"inst0");
  my $inst4 = Some_Instrument->new(gpib=>$iface);


=head2 LOGGING

Logging is implemented with the Moose role MooseX::Log::Log4perl
Initialize Log4perl with:

  use Log::Log4perl qw(:easy);
  Log::Log4perl->easy_init($ERROR);    #Normally quiet logging.

Trace logging is implermented on the channel __PACKAGE__ . ".IOTrace" at level "info".
Turn it on with:
C<Log::Log4perl-E<gt>get_logger("GPIBWrap.IOTrace")-E<gt>level($INFO);>

=head2 Object Attributes

=over 4

=item *

B<connectString> - How to connect to the device, ex: "VXI11::host::instr0"
  or "VXI11::host::hpib,12" or "SICL::host::hpib,12" where host is an IPv4 address or hostname

=item *

B<gpib> - The underlying GPIB interface object for this device. This gets made for you if you use a 
  connectionString. Without a B<gpib>, all calls return; making a dummy device.

=item *

B<bytes_read> - The number of bytes read in the last read operation

=item *

B<reason> - Reason the read terminated


=back

=cut

#
# If we're passed a connectString, use it to instantiate the device.
sub BUILD {
  my $self = shift;
  my $args = shift;
  if ( !length( $self->connectString ) ) { return; }
  Log::Log4perl->init_once();

  #Connection string can be VXI11::host::instr0
  #or VXI11::host::hpib,12 or SICL::host::hpib,12
  my $cs = $self->connectString;
  my ( $proto, $host, $target ) = split( '::', $cs );
  if ( !defined($target) || length($target) == 0 ) {
    $target = "inst0";
  }
  $self->host($host);
  if ( $proto =~ /VXI11/i ) {
    use_module("VXI11::Client");
    VXI11::Client->import();
    $self->gpib( VXI11::Client::vxi_open( address => $host, device => $target ) );
    return;
  }
  if ( $proto =~ /SICL/i ) {
    use_module("RPCINST");
    RPCINST->import();
    my $trmchr = undef;
    if ( ref($args) && defined( $args->{termChr} ) ) {
      $trmchr = $args->{termChr};
    }
    $self->gpib( RPCINST->new( $host, $target, $trmchr ) );
    $self->gpib()->iconnect();
    return;
  }
  return;
}

=head2 METHODS

=over 4

=item B<< $instrument->ilock([$wait]) >>

Get an exclusive lock on the instrument. If $wait is true, wait for the lock.

=back

=cut

sub ilock {
  my $self = shift;
  my $wait = shift;
  return                                                                            if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "ilock %s", $wait ) ) if ( Log::Log4perl->initialized() );
  return                                                                            if ( !defined( $self->gpib ) );
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
      TransportError->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  return                                                                            if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iwrite %s", $arg ) ) if ( Log::Log4perl->initialized() );
  return                                                                            if ( !defined( $self->gpib ) );
  chomp($arg);
  chomp($arg);
  $arg .= "\n";
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_write($arg);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->iwrite($arg);
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  if ( !defined( $self->gpib ) ) {
    $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iread") ) if ( Log::Log4perl->initialized() );
    return ("");
  }
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      my $in = "";
      do {
        ( $self->{bytes_read}, my $xin, $self->{reason} ) = $self->gpib()->vxi_read(@_);
        $in .= $xin;
      } while ( ( $self->{reason} & ( TERM_CHR | TERM_END ) ) == 0 );
      $self->{bytes_read} = length($in);
      $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iread -> %s", $in ) )
        if ( Log::Log4perl->initialized() );
      return ($in);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      my $in = $self->gpib()->iread(@_);
      $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iread -> %s", $in ) )
        if ( Log::Log4perl->initialized() );
      return ($in);
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iquery %s", $arg ) ) if ( Log::Log4perl->initialized() );
  $self->iwrite($arg);
  return ( $self->iread() );
}

=over 4

=item B<< $instrument->iOPC([$timeout]) >>

Very similar to *OPC?, however, if the timeout is specified (in seconds,
fractions are ok), it'll return -1 if the timeout expires. Returns 1 when the
operation in complete. This is a better way to wait for long operations than
*OPC? because lan devices can timeout and the instrument doesn't know it.  This
code will poll every second for the Operation Complete bit in the ESR, thus
avoiding timeouts on the lan.

This will work for IEEE 488.2 compliant instruments, but for others, you'll
probably need to overload this function.

=back

=cut

sub iOPC {
  my $self    = shift;
  my $timeout = shift || $self->defaultTimeout;    #seconds (fractional ok)
  my $ret;
  return if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "iOPC %g", $timeout ) )
    if ( Log::Log4perl->initialized() );
  return if ( !defined( $self->gpib ) );
  $self->iwrite("*ESE 255");                       #Propagate OPC up to STB
  $self->iwrite("*CLS");
  $self->iwrite("*OPC");                           #Tell the instrument we're interested in OPC
  my $tstart = [gettimeofday];

  #Poll STB for ESB bit, then read ESR for OPC
  my $pollInterval = 1.0;
  if ($timeout) {
    while ( tv_interval($tstart) <= $timeout ) {
      my $stb = $self->ireadstb();
      if ( $stb & ( 1 << 5 ) ) {    #Event status bit set?
        my $esr = $self->iquery("*ESR?") || 0;    #Read ESR
        if ( $esr & 0x1 ) {                       #OPC set?
          return (1);
        }
        usleep(500000);                           # 500ms sleep
      }
      my $sleepTime = $timeout - tv_interval($tstart);
      if ( $sleepTime <= 0 ) {
        last;
      }
      $sleepTime = ( $sleepTime >= $pollInterval ) ? $pollInterval : $sleepTime;
      usleep( $sleepTime * 1e6 );
    }    #While timeout

    #If we get here, we timed out.
    $self->log( $self->logsubsys . ".IOTrace" )->error( shortmess("IOPC Timeout") ) if ( Log::Log4perl->initialized() );
    my @errs = $self->getErrors();
    $self->log( $self->logsubsys . ".IOTrace" )->warning( join( "\n", @errs ) ) if ( Log::Log4perl->initialized() );

    #TimeoutError->throw( { err => 'iOPC timeout' });
    return (-1);
  }

  #No timeout case ...
  my $lc = 0;
  while (1) {
    $ret = $self->iquery("*ESR?") || 0;
    if ( $ret & (0x1) ) {
      return (1);
    }

    #$ret = $self->iquery("*OPC?") || 0;
    #last if ( $self->reason() != 0 );
    my $exp = int( $lc / 5 );
    $exp = $exp > 4 ? 4 : $exp;
    sleep( 1 << $exp );    #exponential backoff up to 16 sec.
    $lc++;
  }
  return ( $ret & 0x1 );    #We should never get here
}

=over 4

=item B<< $instrument->id() >>

Shorthand for $instrument->iquery("*IDN?");

=back

=cut

sub id {
  my $self = shift;
  return                                                             if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("id") ) if ( Log::Log4perl->initialized() );
  return                                                             if ( !defined( $self->gpib ) );
  return ( $self->iquery("*IDN?") );
}

=over 4

=item B<< $instrument->icreate_intr_chan() >>

Makes a "thread" to watch for interrupts from the instrument, for, say, SRQ's

=back

=cut

sub icreate_intr_chan {
  my $self = shift;
  return                                                                            if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("icreate_intr_chan") ) if ( Log::Log4perl->initialized() );
  return                                                                            if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_create_intr_chan();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      TransportError->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  if ( !defined( $self->gpib ) ) {
    $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("ireadstb") ) if ( Log::Log4perl->initialized() );
    return (0);
  }
  my $rval = 0;
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $rval = ( $self->gpib()->vxi_readstatusbyte() )[1];
      $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "ireadstb -> 0x%x", $rval ) )
        if ( Log::Log4perl->initialized() );
      return ($rval);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $rval = $self->gpib()->istatus();
      $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "ireadstb -> 0x%x", $rval ) )
        if ( Log::Log4perl->initialized() );
      return ($rval);
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf( "ienablesrq %s", $handle ) )
    if ( Log::Log4perl->initialized() );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_enable_srq($handle);
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      TransportError->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->iwai() >>

Wait for interrupt.

=back

=cut

sub iwai {
  my $self = shift;
  return                                                               if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iwai") ) if ( Log::Log4perl->initialized() );
  return                                                               if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_wait_for_interrupt();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      TransportError->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("idestroy_intr_chan") )
    if ( Log::Log4perl->initialized() );
  return if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_destroy_intr_chan();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      TransportError->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->iabort() >>

Abort the current operation.

=back

=cut

sub iabort {
  my $self = shift;
  return                                                                 if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iabort") ) if ( Log::Log4perl->initialized() );
  return                                                                 if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_abort();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      TransportError->throw( { err => '"RPCINST" not implemented' } );
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->iclear() >>

Effect a Selected Device Clear

=back

=cut

sub iclear {
  my $self = shift;
  return                                                                 if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iclear") ) if ( Log::Log4perl->initialized() );
  return                                                                 if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_clear();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->iclear();
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->itrigger() >>

Send a bus trigger.

=back

=cut

sub itrigger {
  my $self = shift;
  return                                                                   if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("itrigger") ) if ( Log::Log4perl->initialized() );
  return                                                                   if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_trigger();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->itrigger();
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->ilocal() >>

Cause the instrument to go to local control.

=back

=cut

sub ilocal {
  my $self = shift;
  return                                                                 if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("ilocal") ) if ( Log::Log4perl->initialized() );
  return                                                                 if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_local();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->ilocal();
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->iremote() >>

Put the instrument in remote control (local lockout).

=back

=cut

sub iremote {
  my $self = shift;
  return                                                                  if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iremote") ) if ( Log::Log4perl->initialized() );
  return                                                                  if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_remote();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->iremote();
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->iunlock() >>

Give up your lock on the device.

=back

=cut

sub iunlock {
  my $self = shift;
  return                                                                  if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iunlock") ) if ( Log::Log4perl->initialized() );
  return                                                                  if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_unlock();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->iunlock();
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
  }
}

=over 4

=item B<< $instrument->iclose() >>

Close this connection.

=back

=cut

sub iclose {
  my $self = shift;
  return                                                                 if ( !defined($self) );
  $self->log( $self->logsubsys . ".IOTrace" )->info( sprintf("iclose") ) if ( Log::Log4perl->initialized() );
  return                                                                 if ( !defined( $self->gpib ) );
SWITCH: {
    if ( $self->gpib()->isa("VXI11::Client") ) {
      $self->gpib()->vxi_close();
      last(SWITCH);
    }
    if ( $self->gpib()->isa("RPCINST") ) {
      $self->gpib()->idisconnect();
      last(SWITCH);
    }
    TransportError->throw( { err => 'Unknown GPIB transport' } );
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
  my $self    = shift;
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

=over 4

=item B<< $instrument->e2050Reset([$ip]) >>

This is a convenience method to reset and clear errors in an HP E2050
Lan<->HPIB box. If you didn't construct with a connection string, then this
routine must be called with an ip address or hostname for the E2050 (C<$ip>).
ONLY CALL THIS IF YOU'RE TALKING TO AN HP E2050.

=back

=cut

sub e2050Reset {
  my $self = shift;
  my $ip   = shift || $self->host;
  return if ( !length($ip) );
  my $t      = Net::Telnet->new( Timeout => 20, Prompt => '/>\s*/' );
  my $result = $t->open($ip);

  #printf("%s\n",$result?"opened":"didn't open");
  my @return = $t->cmd("reboot");
  $result = $t->print('y');
  return;
}

=over 4

=item B<< $instrument->stringBlockEncode($string) >>

Returns a string suitable for downloading to an instrument with the length
encoded at the front of the string. Encodes the length into 3 digits, so only
works up to 1000 characters.

=back

=cut

sub stringBlockEncode {
  my $self = shift;
  my $str  = shift;
  my $len  = length($str);
  return ( sprintf( "#3%d%s", $len, $str ) );
}

sub trimwhite {
  my $in = shift;
  $in =~ s/^\s+//;
  $in =~ s/\s+$//;
  $in =~ s/\s+/ /;
  return ($in);
}

sub queryform {
  my $in = shift;
  $in = trimwhite($in);
  if ( $in =~ /\s+./ ) {    #A subsystem qualifier or query arg?
    $in =~ s/\s+(.)/? $1/;
  } else {
    $in = $in . '?';
  }
  return ($in);
}

sub enumCheck {
  my $self  = shift;
  my $var   = shift;
  my $allow = shift;
  return (OK) if ( !defined($var) );
  my %all = map { $_ => 1 } @$allow;
  return (ERR) if ( !exists( $all{ uc($var) } ) );
  return (OK);
}

sub argCheck {
  my $self  = shift;
  my $mname = shift;
  my $arg   = shift;
  return (OK) if ( !defined($arg) );
  my $descriptor = $self->instrMethods->{$mname};
  return (OK) if ( !exists( $descriptor->{argcheck} ) );
  if ( $descriptor->{argtype} eq 'ENUM' ) {
    ( OK == $self->enumCheck( $arg, $descriptor->{argcheck} ) )
      || UsageError->throw(
      {
        err => sprintf( "%s requires argument be one of %s", $mname, join( ",", @{ $descriptor->{argcheck} } ) )
      }
      );
  }
  return (OK);
}
my $onoffStateGeneric = sub {
  my $self       = shift;
  my $mname      = shift;
  my $on         = shift;
  my $descriptor = $self->instrMethods->{$mname};
  my $subsys     = $descriptor->{scpi};
  if ( !defined($on) ) {
    $subsys =~ s/STATE/STATE?/;
    my $state = $self->iquery($subsys);
    return ($state);
  }
  $on = ( $on != 0 ) ? 1 : 0;
  $self->iwrite( "$subsys," . $on );
};

#We get here is argtype != NONE
my $scalarSettingGeneric = sub {
  my $self  = shift;
  my $mname = shift;
  my $val   = shift;
  $self->argCheck( $mname, $val );
  my $descriptor = $self->instrMethods->{$mname};
  my $subsys     = $descriptor->{scpi};
  my $queryonly  = $descriptor->{queryonly} || 0;
  if ( !defined($val) ) {
    $val = $self->iquery( queryform($subsys) );
    return ($val);
  }
  if ($queryonly) {
    UsageError->throw( { err => sprintf( "%s is a query only command", $mname ) } );
  }
  $self->iwrite( "$subsys," . $val );
};
my $commandGeneric = sub {
  my $self       = shift;
  my $mname      = shift;
  my $descriptor = $self->instrMethods->{$mname};
  my $subsys     = $descriptor->{scpi};
  my $queryonly  = $descriptor->{queryonly} || 0;
  my $val;
  if ($queryonly) {
    $val = $self->iquery( queryform($subsys) );
    return ($val);
  }
  $self->iwrite("$subsys");
};

# Populate accessor methods for simple scpi commands.
# $self->instrMethods is a hash ref of the form { methodName => { scpi => "scpi:command", argtype=>"sometype",
#         argcheck=>['enumA','enumB',...]}, ... }
#
sub populateAccessors {
  my $self = shift;
  my $args = shift;
  my $meta = $self->meta;
  $self->logsubsys($self);
  foreach my $methodName ( keys( %{ $self->instrMethods } ) ) {

    #printf("populate %s in %s\n",$methodName,$self);
    my $descriptor = $self->instrMethods->{$methodName};
    if ( $descriptor->{argtype} eq "NONE" ) {
      $meta->add_method(
        $methodName => sub {
          my $s   = shift;
          my $arg = shift;
          return ( $commandGeneric->( $s, $methodName ) );
        }
      );
    }
    if ( $descriptor->{argtype} eq "BOOLEAN" ) {
      $meta->add_method(
        $methodName => sub {
          my $s   = shift;
          my $arg = shift;
          return ( $onoffStateGeneric->( $s, $methodName, $arg ) );
        }
      );
    }
    if ( $descriptor->{argtype} eq "NUMBER" || $descriptor->{argtype} eq "ENUM" ) {
      $meta->add_method(
        $methodName => sub {
          my $s   = shift;
          my $arg = shift;
          $arg = uc($arg) if ( defined($arg) && $descriptor->{argtype} eq "ENUM" );
          return ( $scalarSettingGeneric->( $s, $methodName, $arg ) );
        }
      );
    }
  }

  #$meta->make_immutable;
}
1;

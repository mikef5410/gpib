# -*- mode: perl -*-
#
package Agilent_86100;
use Moose;
use namespace::autoclean;
use Time::HiRes     qw(sleep usleep gettimeofday tv_interval);
use Time::Out       qw(timeout);
use Carp            qw(cluck longmess shortmess);
use Module::Runtime qw(use_module use_package_optimistically);
use Exception::Class ( 'IOError', 'TransportError', 'TimeoutError' );
## no critic (ProhibitTwoArgOpen)
## no critic (ValuesAndExpressions::ProhibitAccessOfPrivateData)
## no critic (ProhibitNestedSubs)
## no critic (BitwiseOperators)
with( 'GPIBWrap', 'Throwable', 'CDR' );    #Use Try::Tiny to catch my errors
###############################################################################
###############################################################################
##
##			    SUBROUTINES (METHODs)
##
###############################################################################
###############################################################################
################################################################################
# Reset: Send the *RST command
################################################################################
sub init {
  my $self = shift;
  $self->cdrInit();
}

sub Reset() {
  my $self = shift;
  $self->iwrite('*RST');
  return 0;
}

=over 4

=item B<< $instrument->XiOPC([$timeout]) >>

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

#Calling it XiOPC to disable this method and use the one in GPIBWrap
sub iOPC {
  my $self    = shift;
  my $timeout = shift || $self->defaultTimeout;    #seconds (fractional ok)
  my $ret;
  return if ( !defined($self) );
  $self->log('Agilent86100.IOTrace')->info( sprintf( "iOPC %g", $timeout ) );
  return if ( !defined( $self->gpib ) );
  $self->iwrite("*ESE 255\n");                     #Propagate OPC up to STB
  $self->iwrite("*OPC?\n");                        #Tell the instrument we're interested in OPC
  my $tstart = [gettimeofday];

  #Poll STB for ESB bit, then read ESR for OPC
  my $pollInterval = 1.0;
  if ($timeout) {
    while ( tv_interval($tstart) <= $timeout ) {
      my $stb = $self->ireadstb();

      #$self->log('Agilent86100.IOTrace')->info(sprintf("STB: 0x%x\n",$stb));
      if ( $stb & (0x30) ) {    #MAV bit (4) or ESB bit (5) set?
        my $x = $self->iread();    #$self->log('Agilent86100.IOTrace')->info(sprintf("OPC Read: 0x%x\n",$x));
        return (1);                #Good to go...
      }
      my $sleepTime = $timeout - tv_interval($tstart);
      if ( $sleepTime <= 0 ) {
        last;
      }
      $sleepTime = ( $sleepTime >= $pollInterval ) ? $pollInterval : $sleepTime;
      usleep( $sleepTime * 1e6 );
    }    #While timeout

    #If we get here, we timed out.
    $self->log('Agilent86100.IOTrace')->error( shortmess("IOPC Timeout") );
    $self->iclear();    #Device clear ... the *OPC? timed out...
                        #TimeoutError->throw( { error => 'iOPC timeout' });
    return (-1);
  }

  #No timeout case ...
  my $lc = 0;
  while (1) {
    $ret = $self->ireadstb() || 0;
    if ( $ret & (0x30) ) {
      return (1);
    }

    #$ret = $self->iquery("*OPC?") || 0;
    #last if ( $self->reason() != 0 );
    my $exp = int( $lc / 5 );
    $exp = $exp > 4 ? 4 : $exp;
    sleep( 1 << $exp );    #exponential backoff up to 16 sec.
    $lc++;
  }
  return ($ret);           #We should never get here
}
###############################################################################
#
# $dca->ipresent()	- see if the instrument is responding
#
###############################################################################
sub ipresent {    # overload the pre-defined ipresent()
  my $self = shift;
  my $identity;
  $identity = $self->iquery('*IDN?');
  if ( $identity eq '' ) {
    return 1;    # failure
  } else {
    return 0;    # success - it's here
  }
}
###############################################################################
#
# Autoscale
#
###############################################################################
sub Autoscale {
  my ($self) = shift;
  my ($i)    = 0;       # Counter

  # Autoscale
  $self->iwrite(":AUT");
  $self->iwrite(":AUT?");
  $self->{"auto"} = $self->iread();
  chomp( $self->{"auto"} );
}
###############################################################################
#
# Run
#
###############################################################################
sub Run {
  my ($self) = shift;

  # Run
  $self->iwrite(':RUN');
  return 0;
}
###############################################################################
#
# Stop
#
###############################################################################
sub Stop {
  my ($self) = shift;

  # Stop
  $self->iwrite(":STOP");
}
###############################################################################
#
# Set Precision Time Ref
#
###############################################################################
sub TimeRef_set {
  my ($self) = shift;

  # Set Time Ref
  $self->iwrite(":TIM:PREC:TREF");
  return 0;
}
###############################################################################
#
# Set Precision Time Ref Frequency
#
###############################################################################
sub TimeRef_freq {
  my ($self) = shift;
  my ($freq) = shift;    # Frequency

  # Set Time Ref
  $self->iwrite(":TIM:PREC:RFR $freq");
  return 0;
}
###############################################################################
#
# Query Precision Time Ref
#
###############################################################################
sub TimeRef_Check {
  my ($self) = shift;

  # Check Time Ref status
  $self->iwrite(":TIM:PREC:TREF?");
  $self->{"status"} = $self->iread();
  chomp( $self->{"status"} );
  return $self->{"status"};    # Return to value user
}
###############################################################################
#
# Clear
#
###############################################################################
sub Clear {
  my ($self) = shift;

  # Run
  $self->iwrite(":MEAS:CLEAR");
}
###############################################################################
#
# Clear_Display
#
###############################################################################
sub Clear_Display {
  my ($self) = shift;

  # Run
  $self->iwrite(':CDIS;');
  return 0;
}
###############################################################################
#
# Connect_Display
#
###############################################################################
sub Connect_Display {
  my ($self) = shift;
  my $value = shift || 'OFF';
  $self->iwrite(":DISP:CONN $value ");
}
###############################################################################
#
# Run Until - This command will poll the instrument until it has reached it's
#   aquistion limits before returning to the the user...
#
###############################################################################
sub Run_Until {

  # Call this routine -AFTER- having already called Run().
  my ($self) = shift;
  my ($type) = shift || 'WAV';    # WAVeforms [default] | SAMples | OFF
  my ($pts)  = shift || 200;      # Number of points
  my ($alert);

  # Run Until
  $self->iwrite(':ALER?');        # (To clear flag...)
  $self->iread();                 # Read INSTR response (Flag cleared...)
  if ( $type =~ /off/i ) {
    $self->iwrite(':ACQ:RUNT OFF');
    $self->iwrite(':CDIS');
    return 0;
  }
  $type = ( $type =~ /wav/i ? 'WAV' : 'SAM' );    # Clean up user param...
  $self->iwrite(":ACQ:RUNT $type,$pts");

  # Be very careful here. $alert will be set to something
  # that evaluates to 0 but still looks 'set'.  e.g. '+0'.
  # Here is compared the evaluation to 0; not the value...
  $alert = 0;                # seed for first iteration
  while ( $alert == 0 ) {    # While aquisition is not done...
    $self->iwrite(':ALER?');
    $alert = $self->iread();    # Read INSTR response
    chomp($alert);
    last if ( $alert != 0 );    # early exit
                                #select( undef, undef, undef, 0.5 );    # Wait half a sec.
    sleep(0.5);

    #print "Alert: $alert\n";
  }
  return 0;
}
###############################################################################
#
# Run_Until_Results Run until the results are good
#
###############################################################################
sub Run_Until_Results {
  my ($self)  = shift;
  my ($count) = shift || 50;     # Starting count
  my ($quit)  = shift || 200;    # Quit count
  $self->Run();                  # start measuring
  $self->Run_Until( 'WAV', $count );
  my ( $res, $check, @val );
  $check = 1;
  while ($check) {
    $self->iwrite(':MEAS:RESULTS?');
    $res   = $self->iread();
    @val   = split /\)\,/, $res;    # split on weird boundary
                                    # typical bad result is like "Rise time(3),9.99999E+37,..."
    $check = 0;
    for (@val) {
      $check = 1 if (m/^9\.99999E\+37,/);
    }

    #print "check is $check for count $count\n";
    last unless $check;
    $count += 10;                   # try 10 more measurements
    last if ( $count > $quit );
    $self->Run();                   # start measuring again
    $self->Run_Until( 'WAV', $count );
  }
  return 0;
}
###############################################################################
#
# Set Time Range
#
###############################################################################
sub Range_set {
  my ($self)  = shift;
  my ($range) = shift;    # Note range

  # Set range
  $self->iwrite(":TIM:RANG $range");
  return 0;

  #$self->iwrite(":TIM:RANG?");
  #$self->{"trng"}=$self->iread();
  #chomp($self->{"trng"});
  #return $self->{"trng"};		# Return to value user
}
###############################################################################
#
# Set Time Base Scale (time/division)
# Not use in Jitter Mode
#
###############################################################################
sub Scale_set {
  my ($self) = shift;
  my ($val)  = shift || '200E-12';    # ps
  $self->iwrite(":TIM:SCAL $val");
  return 0;
}
###############################################################################
#
# Query - Get the vertical scale per division
#
###############################################################################
sub Get_ChScale {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  $self->iwrite(":CHAN$ch:SCAL?");
  $self->{"chscale$ch"} = $self->iread();
  chomp( $self->{"chscale$ch"} );
  return $self->{"chscale$ch"};    # Return to value user
}
###############################################################################
# Get Time Range
# The full-scale horizontal time in seconds, 10 divisions
###############################################################################
sub Get_Range_set {
  my $self = shift;
  $self->iwrite(":TIM:RANG?");
  $self->{x_range} = $self->iread();
  chomp( $self->{x_range} );
  return $self->{x_range};
}
###############################################################################
#
# Set Delay Reference
#
###############################################################################
sub Time_ref {
  my ($self) = shift;
  my ($ref)  = shift;    # Note reference, LEFT | CENTer

  # Set range
  $self->iwrite(":TIM:REF $ref");
  return 0;
}
###############################################################################
#
# Timebase Position
#
###############################################################################
sub Time_pos {
  my ($self) = shift;
  my ($val)  = shift || '24.0E-9';    # Unit: sec

  # Set Timebase interval between trigger and reference point.
  $self->iwrite(":TIM:POS $val");
  return 0;                           # Return to value user
}
###############################################################################
#
# Query Timebase Position
#
###############################################################################
sub Get_Time_pos {
  my ($self) = shift;

  # Get Timebase interval between trigger and reference point.
  $self->iwrite(":TIM:POS?");
  $self->{"tpos"} = $self->iread();
  chomp( $self->{"tpos"} );
  return $self->{"tpos"};    # Return to value user
}
###############################################################################
#
# Query Peak-to-Peak Voltage
#
###############################################################################
sub Vppk {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Vppk
  $self->iwrite(":MEAS:VPP? CHAN$ch");
  $self->{"vpp$ch"} = $self->iread();
  chomp( $self->{"vpp$ch"} );
  return $self->{"vpp$ch"};    # Return to value user
}
###############################################################################
#
# Measure Peak-to-Peak Voltage
#
###############################################################################
sub Vppk_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure rise time
  $self->iwrite(":MEAS:VPP CHAN$ch");
}
###############################################################################
#
# Query Average Voltage
#
###############################################################################
sub Vavg {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Vavg
  $self->iwrite(":MEAS:VAV? CYCLE,CHAN$ch");
  $self->{"vavg$ch"} = $self->iread();
  chomp( $self->{"vavg$ch"} );
  return $self->{"vavg$ch"};    # Return to value user
}
###############################################################################
# DutyCycle Measurement
# Dutycycle [%] = (Positive Pulse Width/Period)*(100)
###############################################################################
sub DutyCycle_measure {
  my $self = shift;
  my $ch   = shift;    # Note channel to take meas on
  $self->iwrite(":MEAS:DUTY CHAN$ch");
  return 0;
}
###############################################################################
#
# Query DutyCycle - Something bogus here...
#
###############################################################################
sub DutyCycle {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Duty Cycle
  $self->iwrite(":MEAS:DUTY? CHAN$ch");
  $self->{"duty$ch"} = $self->iread();
  chomp( $self->{"duty$ch"} );
  return $self->{"duty$ch"};    # Return to value user
}
###############################################################################
#
# Query waveform period
#
###############################################################################
sub Period {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure waveform period
  $self->iwrite(":MEAS:PER? CHAN$ch");
  $self->{"per$ch"} = $self->iread();
  chomp( $self->{"per$ch"} );
  return $self->{"per$ch"};    # Return to value user
}
###############################################################################
#
# Measure waveform Period
#
###############################################################################
sub Period_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure RMS Jitter
  $self->iwrite(":MEAS:PER CHAN$ch");
}
###############################################################################
#
# Query Pulse Width
#
###############################################################################
sub Pwid {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Pulse Width
  $self->iwrite(":MEAS:PWID? CHAN$ch");
  $self->{"pwid$ch"} = $self->iread();
  chomp( $self->{"pwid$ch"} );
  return $self->{"pwid$ch"};    # Return to value user
}
###############################################################################
#
# Query waveform frequency
#
###############################################################################
sub Frequency {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure waveform period
  $self->iwrite(":MEAS:FREQ? CHAN$ch");
  $self->{"frq$ch"} = $self->iread();
  chomp( $self->{"frq$ch"} );
  return $self->{"frq$ch"};    # Return to value user
}
###############################################################################
#
# Query Rise Time
#
###############################################################################
sub Trise {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure rise time
  $self->iwrite(":MEAS:RIS? CHAN$ch");
  $self->{"tr$ch"} = $self->iread();
  chomp( $self->{"tr$ch"} );
  return $self->{"tr$ch"};    # Return to value user
}
###############################################################################
#
# Measure Rise Time
#
sub Trise_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure rise time
  $self->iwrite(":MEAS:RIS CHAN$ch");
}
###############################################################################
#
# Query Fall Time
#
###############################################################################
sub Tfall {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure fall time
  $self->iwrite(":MEAS:FALL? CHAN$ch");
  $self->{"tf$ch"} = $self->iread();
  chomp( $self->{"tf$ch"} );
  return $self->{"tf$ch"};    # Return to value user
}
###############################################################################
#
# Measure Fall Time
#
###############################################################################
sub Tfall_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure fall time
  $self->iwrite(":MEAS:FALL CHAN$ch");
}
###############################################################################
#
# Query Maximum voltage
#
###############################################################################
sub Vmax {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Maximum voltage level
  $self->iwrite(":MEAS:VMAX? CHAN$ch");
  $self->{"vmax$ch"} = $self->iread();
  chomp( $self->{"vmax$ch"} );
  return $self->{"vmax$ch"};    # Return to value user
}
###############################################################################
#
# Query Minimum voltage
#
###############################################################################
sub Vmin {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Minimum voltage level
  $self->iwrite(":MEAS:VMIN? CHAN$ch");
  $self->{"vmin$ch"} = $self->iread();
  chomp( $self->{"vmin$ch"} );
  return $self->{"vmin$ch"};    # Return to value user
}
###############################################################################
#
# Measure Amplitude voltage (Vtop-Vbase)
#
###############################################################################
sub Vampl_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure fall time
  $self->iwrite(":MEAS:VAMP CHAN$ch");
}
###############################################################################
#
# Query Amplitude voltage (Vtop-Vbase)
#
###############################################################################
sub Vampl {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  $self->iwrite(":MEAS:VAMP? CHAN$ch");
  $self->{"vampl$ch"} = $self->iread();
  chomp( $self->{"vampl$ch"} );
  return $self->{"vampl$ch"};    # Return to value user
}
###############################################################################
#
# Query RMS
#
###############################################################################
sub Vrms_DC {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure DC rms voltage
  $self->iwrite(":MEAS:VRMS? CYCL,DC,CHAN$ch");
  $self->{"vrmsdc$ch"} = $self->iread();
  chomp( $self->{"vrmsdc$ch"} );
  return $self->{"vrmsdc$ch"};    # Return to value user
}
###############################################################################
#
# Set Manual Marker Y1 Position
#
###############################################################################
sub Y1_position {
  my ($self) = shift;
  my ($pos)  = shift;    # Y1 Position, current meas unit value
  my ($CH)   = shift;    # Marker Source

  # Set marker Y1 position
  $self->iwrite(":MARK:Y1P $pos");
}
###############################################################################
#
# Set Manual Marker Y2 Position
#
###############################################################################
sub Y2_position {
  my ($self) = shift;
  my ($pos)  = shift;    # Y2 Position, current meas unit value
  my ($CH)   = shift;    # Marker Source

  # Set marker Y2 position
  $self->iwrite(":MARK:Y2P $pos");
}
###############################################################################
#
# Query Logic 1/0 Levels - EYE mode only
#
###############################################################################
sub LogicOne_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Logic One level
  $self->iwrite(":MEAS:CGR:OLEV CHAN$ch");
}

sub LogicZero_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Logic Zero level
  $self->iwrite(":MEAS:CGR:ZLEV CHAN$ch");
}

sub Logic_Levels {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Logic 1 level
  $self->iwrite(":MEAS:CGR:OLEV? CHAN$ch");
  $self->{"logic1$ch"} = $self->iread();
  chomp( $self->{"logic1$ch"} );

  # Measure Logic 1 level
  $self->iwrite(":MEAS:CGR:ZLEV? CHAN$ch");
  $self->{"logic0$ch"} = $self->iread();
  chomp( $self->{"logic0$ch"} );
  return ( $self->{"logic0$ch"}, $self->{"logic1$ch"} ) if wantarray;
  return 0;
}
###############################################################################
#
# Query Logic 1 Level - EYE mode only
#
###############################################################################
sub Logic1_Level {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Logic 1 level
  $self->iwrite(":MEAS:CGR:OLEV? CHAN$ch");
  $self->{"logic1$ch"} = $self->iread();
  chomp( $self->{"logic1$ch"} );
  return $self->{"logic1$ch"};    # Return to value user
}
###############################################################################
#
# Query Logic 0 Level - EYE mode only
#
###############################################################################
sub Logic0_Level {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure Logic 1 level
  $self->iwrite(":MEAS:CGR:ZLEV? CHAN$ch");
  $self->{"logic0$ch"} = $self->iread();
  chomp( $self->{"logic0$ch"} );
  return $self->{"logic0$ch"};    # Return to value user
}
###############################################################################
#
# Set Rise & Fall time threshold to 80%,50%,20%
#
###############################################################################
sub Rise_Fall_Threshold {
  my ($self)      = shift;
  my ($threshold) = shift || "805020";    # "905010" or "805020"
  $threshold =~ m/(\d\d)(\d\d)(\d\d)/;
  my ($upper) = $1 || 80;                 # Values in percent
  my ($mid)   = $2 || 50;                 # Values in percent
  my ($lower) = $3 || 20;                 # Values in percent
  $self->iwrite(":MEAS:DEF THR,PERC,$upper,$mid,$lower");
}
###############################################################################
#
# Query RMS Jitter
#
###############################################################################
sub Jitter_RMS {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure RMS Jitter
  $self->iwrite(":MEAS:CGR:JITT? RMS,CHAN$ch");
  $self->{"jrms$ch"} = $self->iread();
  chomp( $self->{"jrms$ch"} );
  return $self->{"jrms$ch"};    # Return to value user
}
###############################################################################
#
# Measure RMS Jitter
#
###############################################################################
sub JitRMS_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure RMS Jitter
  $self->iwrite(":MEAS:CGR:JITT RMS,CHAN$ch");
}
###############################################################################
#
# Query PPK Jitter
#
###############################################################################
sub Jitter_PPK {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure PPK Jitter
  $self->iwrite(":MEAS:CGR:JITT? PP,CHAN$ch");
  $self->{"jppk$ch"} = $self->iread();
  chomp( $self->{"jppk$ch"} );
  return $self->{"jppk$ch"};    # Return to value user
}
###############################################################################
#
# Measure PPK Jitter
#
###############################################################################
sub JitPPK_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure PPK Jitter
  $self->iwrite(":MEAS:CGR:JITT PP,CHAN$ch");
}
###############################################################################
#
# Query Crossing Percentage
#
###############################################################################
sub Crossing {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure crossing percentage
  $self->iwrite(":MEAS:CGR:CROS? CHAN$ch");
  $self->{"cros$ch"} = $self->iread();
  chomp( $self->{"cros$ch"} );
  return $self->{"cros$ch"};    # Return to value user
}
###############################################################################
#
# Measure Crossing Percentage
#
###############################################################################
sub Crossing_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye amplitude
  $self->iwrite(":MEAS:CGR:CROS CHAN$ch");
}
###############################################################################
#
# Query Eye Height
#
###############################################################################
sub EYE_height {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye height
  $self->iwrite(":MEAS:CGR:EHE? RAT,CHAN$ch");
  $self->{"eyeh$ch"} = $self->iread();
  chomp( $self->{"eyeh$ch"} );
  return $self->{"eyeh$ch"};    # Return to value user
}
###############################################################################
#
# Query Delta Time - NFG???
#
###############################################################################
sub Delta_Time {
  my ($self) = shift;
  my ($src1) = shift || '1';    # Note channel to take meas on
  my ($src2) = shift || '2';    # Note channel to take meas on

  # Measure Delta Time
  $self->iwrite(":MEAS:DELT CHAN$src1,CHAN$src2");
  $self->iwrite(":MEAS:DELT? $src1,$src2");
  $self->{"tdelta"} = $self->iread();

  #printf STDERR "%s\n",$self->{"tdelta"};
  chomp( $self->{"tdelta"} );
  return $self->{"tdelta"};     # Return to value user
}
###############################################################################
#
# Time Edge
#
###############################################################################
sub Time_edge {
  my ($self)      = shift;
  my ($src1)      = shift || '1';    # Note channel to take meas on
  my ($slope)     = shift || '+';
  my ($occurance) = shift || '1';
  my $edge;
  $self->iwrite(":MEAS:TEDG? MIDD,$slope$occurance,CHAN$src1");
  $edge = $self->iread();
  chomp($edge);
  return $edge;                      # Return to value user
}
###############################################################################
#
#  Measure Eye height
#
###############################################################################
sub Height_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  my $eye;

  # Measure eye height
  $self->iwrite(":MEAS:CGR:EHE RAT,CHAN$ch");
}
###############################################################################
#
# Query Eye Amplitude
#
###############################################################################
sub EYE_amplitude {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  my $eye;

  # Measure eye amplitude
  $self->iwrite(":MEAS:CGR:AMPL? CHAN$ch");
  $eye = $self->iread();
  chomp($eye);
  return $eye;           # Return to value user
}
###############################################################################
#
# Measure Eye Amplitude
#
###############################################################################
sub Ampl_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye amplitude
  $self->iwrite(":MEAS:CGR:AMPL CHAN$ch");
}
###############################################################################
#
# Query Eye Bit Rate
#
###############################################################################
sub EYE_bitrate {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure bitrate
  $self->iwrite(":MEAS:CGR:BITR? CHAN$ch");
  $self->{"eyebr$ch"} = $self->iread();
  chomp( $self->{"eyebr$ch"} );
  return $self->{"eyebr$ch"};    # Return to value user
}
###############################################################################
#
# Measure Eye Bit Rate
#
###############################################################################
sub BITR_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye amplitude
  $self->iwrite(":MEAS:CGR:BITR CHAN$ch");
}
###############################################################################
#
# Query Eye duty cycle distortion
#
###############################################################################
sub Duty_distortion {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye height
  $self->iwrite(":MEAS:CGR:DCD? TIME,CHAN$ch");
  $self->{"eyed$ch"} = $self->iread();
  chomp( $self->{"eyed$ch"} );
  return $self->{"eyed$ch"};    # Return to value user
}
###############################################################################
#
# Query Eye width
#
###############################################################################
sub EYE_width {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye height
  $self->iwrite(":MEAS:CGR:EWID? TIME,CHAN$ch");
  $self->{"eyew$ch"} = $self->iread();
  chomp( $self->{"eyew$ch"} );
  return $self->{"eyew$ch"};    # Return to value user
}
###############################################################################
#
# Measure Eye width
#
###############################################################################
sub EWID_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye amplitude
  $self->iwrite(":MEAS:CGR:EWID TIME,CHAN$ch");
}
###############################################################################
#
# Clear the measurement results
#
###############################################################################
sub Clear_Measurement {
  my ($self) = shift;
  $self->iwrite(":MEAS:CLEAR");
}
###############################################################################
#
# change oscope mode to eye/mask
#
###############################################################################
sub EYE_mode {
  my ($self) = shift;

  # Change mode to Eye/Mask mode
  $self->iwrite(':SYST:MODE EYE');
  return 0;
}
###############################################################################
#
# Change Eye mode to Oscope
#
###############################################################################
sub Oscope_mode {
  my ($self) = shift;

  # Change mode to Oscope mode
  $self->iwrite(":SYST:MODE OSC");
}
###############################################################################
#
# Turn on Annotations
#
# Annotations are the on-waveform pointers; not the measure tab
###############################################################################
sub Annotations {
  my ($self)   = shift;
  my ($status) = shift;

  # turn on annotations
  $self->iwrite(":MEAS:ANN $status");
  return 0;
}
##############################################################################
#
# Change EYE mode to TDR
#
###############################################################################
sub TDR_mode {
  my ($self) = shift;

  # Change mode to TDR mode
  $self->iwrite(":SYST:MODE TDR");
  return 0;
}
##############################################################################
#
# Calibrate left or right modules; also get cal for all other routines
# $dca->Cal( \$DCAcal );
#
###############################################################################
# sub Cal {
#   my ($self) = shift;
#   my ($calset_) = shift;    # Calset output
#   my (%args) = ( QUERY => undef, @_ );
#   my $query = $args{QUERY};
#   sub CalModule {
#     my $self   = shift;
#     my $module = shift;
#     if ( $module =~ /l/i ) {
#       $module = "LMOD";
#     } else {
#       $module = "RMOD";
#     }
#     # Start calibration
#     $self->iwrite(":CAL:MOD:VERT $module");    # Send INSTR cmmnd
#     $self->iwrite(":CAL:MOD:CONT");            # Send INSTR cmmnd
#     unless ( 'yes' eq cal_recall_query( $query, 'Skip Calibration of the DCA modules?' ) ) {
#       CalModule( $self, 'LMOD' )
#         if ( 'yes' eq yesno('Calibrate the LEFT module now?') );
#       hold('Let me know when its done');
#       CalModule( $self, 'RMOD' )
#         if ( 'yes' eq yesno('Calibrate the RIGHT Module now?') );
#       hold('Let me know when its done');
#     }
#     # create quick and dirty calset...
#     # this should be forward compatible
#     $$calset_ = $self;
#     return 0;
#   }
# }
###############################################################################
#
# Query Eye Signal-to-Noise
#
###############################################################################
sub EYE_SN {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye SNR
  $self->iwrite(":MEAS:CGR:ESN? CHAN$ch");
  $self->{"eyesn$ch"} = $self->iread();
  chomp( $self->{"eyesn$ch"} );
  return $self->{"eyesn$ch"};    # Return to value user
}
###############################################################################
#
# Measure Eye Signal-to-Noise
#
###############################################################################
sub SN_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on

  # Measure eye SNR
  $self->iwrite(":MEAS:CGR:ESN CHAN$ch");
}

sub Avg {
  my ($self) = shift;
  my ($n)    = shift;    # Number of averages (0 == Off)

  # Set Averaging
  if ( $n == 0 ) {
    $self->iwrite(":ACQ:AVER OFF");
  } else {
    $self->iwrite(":ACQ:AVER ON");
    $self->iwrite(":ACQ:COUN $n");
  }

  # Poll Averaging state
  $self->iwrite(":ACQ:AVER?");
  $self->{avg} = $self->iread();
  $self->{avg} = ( $self->{avg} == 0 ? "Off" : "On" );    # in English...
  chomp( $self->{avg} );

  # Number of averages
  $self->iwrite(":ACQ:COUNt?");
  $self->{avgn} = $self->iread();
  chomp( $self->{avgn} );
}

sub QuerySetup {
  my ($self) = shift;

  # Instrument ID
  $self->iwrite("*IDN?");
  $self->{idn} = $self->iread();
  chomp( $self->{idn} );

  # Mainframe Model
  $self->iwrite(":MOD? FRAM;");
  $self->{modf} = $self->iread();
  chomp( $self->{modf} );

  # Left module Model
  $self->iwrite(":MOD? LMOD;");
  $self->{modl} = $self->iread();
  chomp( $self->{modl} );

  # Right module Model
  $self->iwrite(":MOD? RMOD;");
  $self->{modr} = $self->iread();
  chomp( $self->{modr} );

  # Averaging on?
  $self->iwrite(":ACQ:AVER?");
  $self->{avg} = $self->iread();
  $self->{avg} = ( $self->{avg} == 0 ? "Off" : "On" );    # in English...
  chomp( $self->{avg} );

  # Number of averages
  $self->iwrite(":ACQ:COUNt?");
  $self->{avgn} = $self->iread();
  chomp( $self->{avgn} );

  # Number of points
  $self->iwrite(":ACQ:POIN?");
  $self->{pts} = $self->iread();
  chomp( $self->{pts} );

  # RUN until?
  $self->iwrite(":ACQ:RUNT?");
  $self->{runt} = $self->iread();

  #$self->{runt}=($self->{runt} == 0 ? "OFF" :$self->{runt}); # in English...
  chomp( $self->{runt} );

  # Mainframe calibration time
  $self->iwrite(":CAL:FRAM:TIME?");
  $self->{cft} = $self->iread();
  chomp( $self->{cft} );

  # Module calibration info (left module)
  $self->iwrite(":CAL:MOD:STAT? LMOD");
  $self->{cmsl} = $self->iread();
  chomp( $self->{cmsl} );

  # Module calibration info (right  module)
  $self->iwrite(":CAL:MOD:STAT? RMOD");
  $self->{cmsr} = $self->iread();
  chomp( $self->{cmsr} );

  # Module calibration time (left module)
  $self->iwrite(":CAL:MOD:TIME? LMOD");
  $self->{cmtl} = $self->iread();
  chomp( $self->{cmtl} );

  # Module calibration time (right module)
  $self->iwrite(":CAL:MOD:TIME? RMOD");
  $self->{cmtr} = $self->iread();
  chomp( $self->{cmtr} );

  # Horizontal time range
  $self->iwrite(":TIM:RANG?");
  $self->{trng} = $self->iread();
  chomp( $self->{trng} );

  # Time reference
  $self->iwrite(":TIM:REF?");
  $self->{tref} = $self->iread();
  chomp( $self->{tref} );

  # Time scale
  $self->iwrite(":TIM:SCAL?");
  $self->{tscl} = $self->iread();
  chomp( $self->{tscl} );

  # Time Skew
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CAL:SKEW? CHAN1");
    $self->{skw1} = $self->iread();
    chomp( $self->{skw1} );
    $self->iwrite(":CAL:SKEW? CHAN2");
    $self->{skw2} = $self->iread();
    chomp( $self->{skw2} );
  }

  # Trigger Attenuation
  $self->iwrite(":TRIG:ATT?");
  $self->{tratt} = $self->iread();
  chomp( $self->{tratt} );

  # Trigger gatting
  $self->iwrite(":TRIG:GAT?");
  $self->{trgt} = $self->iread();
  $self->{trgt} = ( $self->{trgt} == 0 ? "Off" : "On" );    # in English...
  chomp( $self->{trgt} );

  # Trigger Hysteresis
  $self->iwrite(":TRIG:HYST?");
  $self->{trhist} = $self->iread();
  chomp( $self->{trhist} );

  # Trigger Level
  $self->iwrite(":TRIG:LEV?");
  $self->{trlev} = $self->iread();
  chomp( $self->{trlev} );

  # Trigger Slope
  $self->iwrite(":TRIG:SLOP?");
  $self->{trslp} = $self->iread();
  chomp( $self->{trslp} );

  # Trigger Source
  $self->iwrite(":TRIG:SOUR?");
  $self->{trsrc} = $self->iread();
  chomp( $self->{trsrc} );
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CAL:SKEW? CHAN3");
    $self->{skw3} = $self->iread();
    chomp( $self->{skw3} );
    $self->iwrite(":CAL:SKEW? CHAN4");
    $self->{skw4} = $self->iread();
    chomp( $self->{skw4} );
  }

  # Channel Bandwidth
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CHAN1:BAND?");
    $self->{bw1} = $self->iread();
    chomp( $self->{bw1} );
    $self->{bw1} = ( $self->{bw1} eq "LOW" ? "26.5 GHz" : "50 GHz" );
    $self->iwrite(":CHAN2:BAND?");
    $self->{bw2} = $self->iread();
    chomp( $self->{bw2} );
    $self->{bw2} = ( $self->{bw2} eq "LOW" ? "26.5 GHz" : "50 GHz" );
  }
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CHAN3:BAND?");
    $self->{bw3} = $self->iread();
    chomp( $self->{bw3} );
    $self->{bw3} = ( $self->{bw3} eq "LOW" ? "26.5e9" : "50e9" );
    $self->iwrite(":CHAN4:BAND?");
    $self->{bw4} = $self->iread();
    chomp( $self->{bw4} );
    $self->{bw4} = ( $self->{bw4} eq "LOW" ? "26.5e9" : "50e9" );
  }

  # Channel Offsets
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CHAN1:OFFS?");
    $self->{ofs1} = $self->iread();
    chomp( $self->{ofs1} );
    $self->iwrite(":CHAN2:OFFS?");
    $self->{ofs2} = $self->iread();
    chomp( $self->{ofs2} );
  }
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CHAN3:OFFS?");
    $self->{ofs3} = $self->iread();
    chomp( $self->{ofs3} );
    $self->iwrite(":CHAN4:OFFS?");
    $self->{ofs4} = $self->iread();
    chomp( $self->{ofs4} );
  }

  # Channel Range
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CHAN1:RANG?");
    $self->{rng1} = $self->iread();
    chomp( $self->{rng1} );
    $self->iwrite(":CHAN2:RANG?");
    $self->{rng2} = $self->iread();
    chomp( $self->{rng2} );
  }
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CHAN3:RANG?");
    $self->{rng3} = $self->iread();
    chomp( $self->{rng3} );
    $self->iwrite(":CHAN4:RANG?");
    $self->{rng4} = $self->iread();
    chomp( $self->{rng4} );
  }

  # Channel Scale
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CHAN1:SCAL?");
    $self->{scl1} = $self->iread();
    chomp( $self->{scl1} );
    $self->iwrite(":CHAN2:SCAL?");
    $self->{scl2} = $self->iread();
    chomp( $self->{scl2} );
  }
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CHAN3:SCAL?");
    $self->{scl3} = $self->iread();
    chomp( $self->{scl3} );
    $self->iwrite(":CHAN4:SCAL?");
    $self->{scl4} = $self->iread();
    chomp( $self->{scl4} );
  }

  # Channel Units
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CHAN1:UNIT?");
    $self->{unit1} = $self->iread();
    chomp( $self->{unit1} );
    $self->iwrite(":CHAN2:UNIT?");
    $self->{unit2} = $self->iread();
    chomp( $self->{unit2} );
  }
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CHAN3:UNIT?");
    $self->{unit3} = $self->iread();
    chomp( $self->{unit3} );
    $self->iwrite(":CHAN4:UNIT?");
    $self->{unit4} = $self->iread();
    chomp( $self->{unit4} );
  }

  # Channel Attn
  if ( $self->{modl} =~ /8348/ ) {
    $self->iwrite(":CHAN1:UNIT:ATT?");
    $self->{uatt1} = $self->iread();
    chomp( $self->{uatt1} );
    $self->iwrite(":CHAN2:UNIT:ATT?");
    $self->{uatt2} = $self->iread();
    chomp( $self->{u2} );
  }
  if ( $self->{modr} =~ /8348/ ) {
    $self->iwrite(":CHAN3:UNIT:ATT?");
    $self->{uatt3} = $self->iread();
    chomp( $self->{uatt3} );
    $self->iwrite(":CHAN4:UNIT:ATT?");
    $self->{uatt4} = $self->iread();
    chomp( $self->{uatt4} );
  }
}
###############################################################################
#
# Display()
#   Send a message to the Oscope display
#
###############################################################################
sub Display {
  my ($self)   = shift;
  my ($string) = shift;    # Store incoming string
  $string =~ s/\%/%%/g;
  $self->iwrite(":SYST:DSP \"$string\"");
  return 0;
}
###############################################################################
#
# Ch_Display()
#   Turn on/off diff Channels
#
###############################################################################
sub Ch_Display {
  my ($self)   = shift;
  my ($ch)     = shift;           # Store incoming string
  my ($status) = shift;           # Store incoming string
  my ($append) = shift || "1";    # APPend (for Eye/Mask mode)
  $append = ( $append =~ /1|yes|app/i ? ",APPend" : "" );
  $self->iwrite( ":CHAN" . "$ch" . ":DISP $status$append" );
  return 0;
}
###############################################################################
#
# Ch_Display_Eye()
# Turn on/off diff Channels, EYE mode "APPend".
#
###############################################################################
sub Ch_Display_Eye {
  my ($self)   = shift;
  my ($ch)     = shift;            # 1 to 4
  my ($status) = shift || "on";    # ON || OFF
  my ($append) = shift || "1";     # APPend (for Eye/Mask mode)
  $append = ( $append =~ /1|yes|app/i ? ",APPend" : "" );
  $self->iwrite( ":CHAN" . "$ch" . ":DISP $status$append" );
}
###############################################################################
#
# ErrorCheck()
#   Poll instrument to see if any errors were reported
#
###############################################################################
sub ErrorCheck {    # Check/Clear Errors
  my ($self)  = shift;
  my ($error) = -1;      # Declare & set a local variable
  my @emess;
  while ( $error !~ /0,no error/i ) {
    $self->iwrite(":SYST:ERR? STR");
    $error = $self->iread();
    chomp($error);
    push @emess, $error if ( $error =~ /0,No error/ );

    #print STDERR $error,"\n" if $error =~ /0,No error/;
  }
  return \@emess;
}
###############################################################################
###############################################################################
##
##                         CHANNEL COMMANDS
##
###############################################################################
###############################################################################
###############################################################################
#
# Ch_Offset() - Channel Offset
#
###############################################################################
sub Ch_Offset {
  my ($self)  = shift;
  my ($ch)    = shift;    # Store incoming string
  my ($value) = shift;    # Store incoming string
  $self->iwrite( ":CHAN" . "$ch" . ":OFFSET $value" );
  return 0;
}
###############################################################################
# Query - Get Channel Offset Voltage
###############################################################################
sub Get_ChOffset {
  my $self = shift;
  my $ch   = shift;       # Note channel to take meas on
  $self->iwrite(":CHAN$ch:OFFSET?");
  $self->{"choff$ch"} = $self->iread();
  chomp( $self->{"choff$ch"} );
  return $self->{"choff$ch"};    # Return to value user
}
###############################################################################
#
# Ch_Range() - Channel amplitude scale-per-div
#
###############################################################################
sub Ch_Range {
  my ($self)  = shift;
  my ($ch)    = shift;                                   # Store incoming string
  my ($value) = shift;                                   # Store incoming string
  $value = sprintf( "%.3e", $value * 10 * 5 / 6.25 );    # Another scope wierdness...
  $self->iwrite( ":CHAN" . "$ch" . ":RANGE $value" );
}
###############################################################################
#
# Ch_Range2() - Channel amplitude scale-per-div
#
###############################################################################
sub Ch_Range2 {
  my ($self)  = shift;
  my ($ch)    = shift;    # Store incoming string
  my ($value) = shift;    # Store incoming string

  #$value = sprintf("%.3e",$value*10*5/6.25);	# Another scope wierdness...
  $self->iwrite( ":CHAN" . "$ch" . ":RANGE $value" );
}
###############################################################################
#
# Ch_FullRange() - Channel amplitude full range
#
###############################################################################
sub Ch_FullRange {
  my ($self)  = shift;
  my ($ch)    = shift;    # Store incoming string
  my ($value) = shift;    # Store incoming string
  $self->iwrite( ":CHAN" . "$ch" . ":RANGE $value" );
}
###############################################################################
#
# Query - Channel amplitude full range
#
###############################################################################
sub Get_ChRange {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  $self->iwrite(":CHAN$ch:RANG?");

  #  $self->iwrite(":MEAS:VAMP? CHAN$ch");
  $self->{"chrng$ch"} = $self->iread();
  chomp( $self->{"chrng$ch"} );
  return $self->{"chrng$ch"};    # Return to value user
}
###############################################################################
#
#  Set channel attenuator factor and the unit, need to clean up 4/15/08
#
###############################################################################
sub Set_Ch_Att {
  my ($self) = shift;
  my ($ch)   = shift;          # Note channel to take meas on
  my ($val)  = shift || 10;    # The attenuator factor ex 10dB, Decibel or Ratio
  $self->iwrite(":CHAN$ch:PROB $val, DEC");
}
###############################################################################
###############################################################################
##
##                         TRIGGER COMMANDS
##
###############################################################################
###############################################################################
###############################################################################
#  Set Trigger Source
###############################################################################
sub Set_Trigger_Source {
  my ($self) = shift;
  my ($sr)   = shift || "FPAN";    # The source of trigger
  $sr = (
    $sr =~ /fpan/i ? "FPAN"
    : (
      $sr =~ /frun/i ? "FRUN"
      : ( $sr =~ /lmod/i ? "LMOD" : "RMOD" )
    )
  );
  $self->iwrite(":TRIG:SOUR $sr");
}
###############################################################################
#  Set Trigger Slope
###############################################################################
sub Set_Trigger_Slope {
  my ($self) = shift;
  my ($sl)   = shift || "POS";    # The slope of the edge on which to trigger
  $sl = ( $sl =~ /pos/i ? "POS" : "NEG" );
  $self->iwrite(":TRIG:SLOP $sl");
}
###############################################################################
#  Set Trigger Hysteresis
#  Prevent false triggers from occurring on the falling edge due to noise
###############################################################################
sub Set_Trigger_Hys {
  my ($self) = shift;
  my ($th)   = shift || "NORM";    # Selection the trigger hysteresis
  $th = ( $th =~ /norm/i ? "NORM" : "HSEN" );
  $self->iwrite(":TRIG:HYST $th");
}
################################################################################
#  Set Trigger Bandwidth
#  Control the internal lowpass filter and a divider in the 86100A trigger
#  DIV mode only for 86100C with opt 001, from 3GHz to 13 GHz
#  LOW: Filtered: DC-100MHz
#  HIGH: Standard: DC-3.2GHz
###############################################################################
sub Set_Trigger_BW {
  my ($self) = shift;
  my ($bw)   = shift || "HIGH";    # The slope of the edge on which to trigger
  $bw = (
    $bw =~ /high/i
    ? "HIGH"
    : ( $bw =~ /l/i ? "LOW" : 'DIV' )
  );
  $self->iwrite(":TRIG:BWL $bw");
}
###############################################################################
#  Set Trigger_Level
#  The trigger level is the threshold level that the trigger edge must cross
#  in order for the instrument to trigger on that signal.
#  When the input signal crosses this voltage level, the instrument triggers.
###############################################################################
sub Set_Trigger_Level {
  my ($self) = shift;
  my ($l)    = shift;
  $self->iwrite(":TRIG:LEV $l");
}
###############################################################################
#  Set Trigger Pattern Length
#  Command PLENgth:Autodetect used to auto dectect the patteren trigger
#  but we have to set the Pattern lock ON
###############################################################################
sub Set_Trigger_Length {
  my ($self) = shift;
  my ($l)    = shift || 127;    # The length of the pattern trigger 127 for 2^7-1
  $self->iwrite(":TRIG:PLEN $l");
}
###############################################################################
#  Set Trigger Pattern Length Autodetect
###############################################################################
sub Trigger_Pattern_Length_Auto_Detect {
  my $self = shift;
  my $auto = shift || 'ON';
  $auto = ( $auto =~ /on/i ? 'ON' : 'OFF' );
  $self->iwrite(":TRIG:PLEN:AUT $auto");
  $self->iwrite(":TRIG:PLEN:AUT?");
  $self->{"auto"} = $self->iread();
  chomp( $self->{"auto"} );
  return ( $self->{"auto"} );
}
###############################################################################
#  Set Trigger Bitrate Autodetect
###############################################################################
sub Trigger_Bitrate_Auto_Detect {
  my $self = shift;
  my $auto = shift || 'ON';
  $auto = ( $auto =~ /on/i ? 'ON' : 'OFF' );
  $self->iwrite(":TRIG:BRAT:AUT $auto");
  $self->iwrite(":TRIG:BRAT:AUT?");
  $self->{"auto"} = $self->iread();
  chomp( $self->{"auto"} );
  return ( $self->{"auto"} );
}
###############################################################################
#  Set Trigger Data Clock Autodetect
###############################################################################
sub Trigger_Data_Clock_Auto_Detect {
  my $self = shift;
  my $auto = shift || 'ON';
  $auto = ( $auto =~ /on/i ? 'ON' : 'OFF' );
  $self->iwrite(":TRIG:DCDR:AUT $auto");
  $self->iwrite(":TRIG:DCDR:AUT?");
  $self->{"auto"} = $self->iread();
  chomp( $self->{"auto"} );
  return ( $self->{"auto"} );
}
###############################################################################
#  Set Trigger Pattern Lock
#  With 86100C option 001, if the pattern lock is ON together with the Eye/Mask,
#  or Scope Mode: We can view the pattern of the waveform with the sinusoidal trigger
#  With this combination, the pattern trigger (using prescaler) is not needed
#  Very handy
###############################################################################
sub Trigger_Pattern_Lock {
  my $self = shift;
  my $auto = shift || 'ON';
  $auto = ( $auto =~ /on/i ? 'ON' : 'OFF' );
  $self->iwrite(":TRIG:PLOC $auto");
  $self->iwrite(":TRIG:PLOC?");
  $self->{"pl"} = $self->iread();
  chomp( $self->{"pl"} );
  return ( $self->{"pl"} );
}
###############################################################################
###############################################################################
##
##                         DISK COMMANDS
##
###############################################################################
###############################################################################
###############################################################################
#
# Save_Image()
#
###############################################################################
sub Save_Image {
  my ($self)     = shift;
  my ($filename) = shift || "default.gif";           # Store incoming string
  my ($area)     = shift || "SCR";                   # Store screen by default
  my ($image)    = shift || "INV";                   # NORMal/INVert/MONochrome
  $area  = ( $area =~ /grat/i ? "GRAT" : "SCR" );    # RegEx to clean up user param
  $image = (
    $image =~ /norm/i
    ? "NORM"
    : ( $image =~ /mono|bw/i ? "MON" : "INV" )
  );
  $self->iwrite(":DISK:SIM \"$filename\",$area,$image");
}
###############################################################################
#
# Save_Waveform()
#
###############################################################################
sub Save_Waveform {
  my ($self)     = shift;
  my ($ch)       = shift;                     # Scope Channel
  my ($filename) = shift || "default.txt";    # Filename
  my ($format)   = shift || "TEXT";           # File Format
  $ch = (
    $ch =~ /1|one/i ? "1"
    : (
      $ch =~ /2|two/i ? "2"
      : ( $ch =~ /3|three/i ? "3" : "4" )
    )
  );                                          # RegEx to clean up user param
  $format = (
    $format =~ /text/i ? "TEXT"
    : (
      $format =~ /yval/i ? "YVAL"
      : ( $format =~ /verb/i ? "VERB" : "INT" )
    )
  );                                          # RegEx to clean up user param
  $self->iwrite(":DISK:STOR CHAN$ch, \"$filename\",$format");    # Send command
}
###############################################################################
#
# Save_GIF()
#
###############################################################################
sub Save_GIF {
  my ($self)     = shift;
  my ($filename) = shift || "default.gif";    # Store incomming string
  $self->iwrite(":DISPlay:DATA? GIF");
  my ($term_maxcnt) = 50000;                        # Give RPCINST bigger val
  my ($img)         = $self->iread($term_maxcnt);
  $img =~ s/^#(\d)//g;                              # How many digit specify length?
  $img =~ s/^\d{$1}//g;                             # Remove these digits
  my $FILE;
  open( $FILE, ">$filename" ) || die "Couldn't open $filename!  $!\n";
  print $FILE $img;
  close($FILE);
}
###############################################################################
#
# CD()
#
###############################################################################
sub CD {    # Disk operaiton
  my ($self) = shift;
  my ($dir)  = shift || "c:\\User Files";    # Store incoming string
  $self->iwrite(":DISK:CDIR \"$dir\"");
}
###############################################################################
#
# MKDIR()
#
###############################################################################
sub MKDIR {    # Disk operaiton
  my ($self)   = shift;
  my ($dir)    = shift;    # Store incoming string
  my ($prefix) = "";       # Add prefix to dir
                           #my($prefix)="c:\\User Files\\";		# Add prefix to dir

  #$dir="$prefix$dir";
  $self->iwrite(":DISK:MDIR \"$dir\"");
}
###############################################################################
#
# MKDIR_CD()
#
###############################################################################
sub MKDIR_CD {    # Disk operaiton
  my ($self) = shift;
  my ($dir)  = shift;    # Store incoming string
  my (@dirs) = split /[\\|\/]/, $dir;
  for my $i ( 0 .. $#dirs ) {
    $self->MKDIR("$dirs[$i]");
    $self->CD("$dirs[$i]");
  }
}
###############################################################################
#
# DIR()
#
###############################################################################
sub DIR {    # Disk operaiton
  my ($self) = shift;
  $self->iwrite(":DISK:DIR?");
  $self->{dir} = $self->iread();

  #chomp($self->{dir});
  return $self->{dir};
}
###############################################################################
#
# PWD()
#
###############################################################################
sub PWD {    # Disk operaiton
  my ($self) = shift;
  $self->iwrite(":DISK:PWD?");
  $self->{pwd} = $self->iread();
  chomp( $self->{pwd} );
  return $self->{pwd};
}
###############################################################################
###############################################################################
##
##                         SYSTEM COMMANDS
##
###############################################################################
###############################################################################
###############################################################################
#
# Date()
#
###############################################################################
sub Date {
  my ($self)        = shift;
  my (@system_time) = localtime(time);                    # Get 9 fields of time info
  my ($day)         = shift || $system_time[3];           # Day
  my ($month)       = shift || $system_time[4] + 1;       # Month
  my ($year)        = shift || $system_time[5] + 1900;    # Year
  $self->iwrite(":SYST:DATE $day,$month,$year");
  $self->iwrite(":SYST:DATE?");
  $self->iread();
}
###############################################################################
#
# Time()
#
###############################################################################
sub Time {
  my ($self)        = shift;
  my (@system_time) = localtime(time);             # Get 9 fields of time info
  my ($hour)        = shift || $system_time[2];    # Hour
  my ($min)         = shift || $system_time[1];    # Minute
  my ($sec)         = shift || $system_time[0];    # Second
  $self->iwrite(":SYST:TIME $hour,$min,$sec");
  $self->iwrite(":SYST:TIME?");
  $self->iread();
}
###############################################################################
#
# Histogram_Axis()
#
###############################################################################
sub Histogram_Axis {
  my ($self) = shift;
  my ($axis) = shift || 'HOR';    # Argument
  $axis = ( $axis =~ /hor/i ? 'HOR' : 'VERT' );
  $self->iwrite(":HIST:AXIS $axis");
  return 0;

  #$self->iwrite(":HIST:AXIS?");
  #$self->{histaxis}=$self->iread();
  #chomp($self->{histaxis});
  #return $self->{histaxis};
}
###############################################################################
#
# Histogram_Mode()
#
###############################################################################
sub Histogram_Mode {
  my ($self) = shift;
  my ($mode) = shift || '?';    # Argument
  $mode = (
    $mode =~ /\?/
    ? '?'
    : ( $mode =~ /on/i ? 'ON' : 'OFF' )
  );
  $self->iwrite(":HIST:MODE $mode") if $mode !~ /\?/;
  return 0;

  #$self->iwrite(":HIST:MODE?");
  #$self->{histmode}=$self->iread();
  #chomp($self->{histmode});
  #return $self->{histmode};
}
###############################################################################
# Histogram Source
###############################################################################
sub Histogram_Source {
  my $self = shift;
  my $src  = shift || 3;    # Channel
  $self->iwrite(":HIST:SOUR CHAN$src");
  return 0;
}
###############################################################################
#
# Histogram_Border()
#
###############################################################################
sub Histogram_Border {
  my ($self)   = shift;
  my ($border) = shift || 'toggle';    # Argument
  if ( $border =~ /toggle/ ) {
    $self->iwrite(":HIST:WIND:BORD?");    # Send command
    $self->{histbrdr} = $self->iread();
    $border = ( $self->{histbrdr} =~ /on|1/i ? 'OFF' : 'ON' );
  }
  $border = ( $border =~ /on/i ? 'ON' : 'OFF' );
  $self->iwrite(":HIST:WIND:BORD $border");    # Send command
  return 0;

  #$self->iwrite(":HIST:WIND:BORD?");		# Send command
  #$self->{histbrdr}=$self->iread();
  #chomp($self->{histbrdr});
  return $self->{histbrdr};    # Return to user
}
###############################################################################
#
# Histogram_Window()
#
###############################################################################
sub Histogram_Window {
  my ($self)     = shift;
  my ($edge)     = shift || 'x1';    # Argument
  my ($position) = shift || '0';     # Argument
  $edge = (
    $edge =~ /x1/i ? 'X1P'
    : (
      $edge =~ /x2/i ? 'X2P'
      : ( $edge =~ /y1/i ? 'Y1P' : 'Y2P' )
    )
  );
  my ( $command, $offset );

=i_got_this_from_cb
  if($position < 24e-9 && $edge =~ /x/){
    $self->iwrite(":HIST:WIND:$edge?");		# Send command
    $self->{histx1p}=$self->iread();		
    my($x1p)=$self->{histx1p}+$position;	# Relative position change
    $command = (":HIST:WIND:$edge $x1p");	# Send command
    print "Histogram_Window using relative position: $position\n";
  } elsif ($edge =~ /x/){
    $command = (":HIST:WIND:$edge $position");# Send command
  } elsif ($position < 50e-3) {
    $self->iwrite(":HIST:WIND:$edge?");		# Send command
    $self->{histy1p}=$self->iread();		
    my($y1p)=$self->{histy1p}+$position;	# Relative position change
    $command = (":HIST:WIND:$edge $y1p");	# Send command
  } else {
    $command = (":HIST:WIND:$edge $position");# Send command
  }
=cut

  if ( $edge =~ /x/i ) {
    if ( $position < 24e-9 && $edge =~ /x/i ) {
      $self->iwrite(":HIST:WIND:$edge?");         # Send command
      $offset = $self->iread();                   # Read INSTR response
      $offset += $position;                       # Relative position change
      $command = (":HIST:WIND:$edge $offset");    # write command
                                                  #print "Histogram_Window using relative $edge position: $offset\n";
    } else {
      $command = (":HIST:WIND:$edge $position");    # write command
    }
  }
  if ( $edge =~ /y/i ) {
    $command = (":HIST:WIND:$edge $position");      # write command
  }

  #print "HIST:WIND: command is >$command< for edge: $edge position: $position\n";
  $self->iwrite($command);                          # Send command
  return 0;

  #$self->iwrite(":HIST:WIND:X1P?");		# Send command
  #$self->{histwindx}=$self->iread();
  #chomp($self->{histwindx});
}
###############################################################################
#
# Query Histogram Mean
#
###############################################################################
sub Histogram_mean {
  my ($self) = shift;

  # Measure eye height
  $self->iwrite(":MEAS:HIST:MEAN?");
  $self->{"hist_mean"} = $self->iread();
  chomp( $self->{"hist_mean"} );
  return $self->{"hist_mean"};    # Return to value user
}
###############################################################################
#
# Query Histogram Hits
#
###############################################################################
sub Histogram_hits {
  my ($self) = shift;

  # Measure eye height
  $self->iwrite(":MEAS:HIST:HITS?");
  $self->{"hist_hits"} = $self->iread();
  chomp( $self->{"hist_hits"} );
  return $self->{"hist_hits"};    # Return to value user
}
###############################################################################
# Query Histogram the greatest peak
# Return the position of the greatest peak of the histogram
# If there is more than one peak, then it returns the position of the first peak
# from the lower boundary of the histogram window for vertical axis histograms.
# If horizontal axis histograms, it returns the position of the first peak from
# the leftmost boundary of the histogram window
###############################################################################
sub Histogram_ppos {
  my $self = shift;
  $self->iwrite(":MEAS:HIST:PPOSition?");
  $self->{"hist_ppos"} = $self->iread();
  chomp( $self->{"hist_ppos"} );
  return $self->{"hist_ppos"};    # Return to value user
}

sub Set_Waveform_Source {

  # set the waveform source
  my $self   = shift;
  my $source = shift || 'CHAN1';
  $self->iwrite(":WAVeform:SOURce $source");

  #Note: MUST check to see that source has been set
  # otherwise may lead to timeouts later...
  # Nope, even this does not help-- it works here but still leads to
  # iread timeouts in later code (get_waveform_preamble)...  Wierd.
  #$self->iwrite(":WAVeform:SOURce?");
  #$source=$self->iread();
  # Must resort to brute force time delay here...?
  #select( undef, undef, undef, 0.5 );    # 0.5 > t > 0.4
  sleep(0.5);
  return 0;

  #$self->iwrite(":WAVeform:SOURce?");
  #$self->{"wave_src"}=$self->iread();
  #chomp($self->{"wave_src"});
  #return $self->{"wave_src"};			# Return to value user
}

sub Get_Waveform_Preamble {

  # this gets the preamble for the selected waveform memory
  my $self = shift;    # instrument handle
                       #my $source	= shift;    # optional argument for :WAV:SOUR argument
  my ( $raw_preamble, $preamble, @fields );

  #Set_Waveform_Source( $self, $source ) if defined( $source );
  # load the preamble string
  $self->iwrite(':WAVeform:PREamble?');
  $raw_preamble = $self->iread();
  chomp $raw_preamble;

  #print "raw_preamble:\n", $raw_preamble, "\n\n";
  $preamble                          = {};                          # origin of the preamble hash
  @fields                            = split /,/, $raw_preamble;    # split preamble fields
  $preamble->{'format'}              = shift @fields;
  $preamble->{'type'}                = shift @fields;
  $preamble->{'points'}              = shift @fields;
  $preamble->{'count'}               = shift @fields;
  $preamble->{'x_increment'}         = shift @fields;
  $preamble->{'x_origin'}            = shift @fields;
  $preamble->{'x_reference'}         = shift @fields;
  $preamble->{'y_increment'}         = shift @fields;
  $preamble->{'y_origin'}            = shift @fields;
  $preamble->{'y_reference'}         = shift @fields;
  $preamble->{'coupling'}            = shift @fields;
  $preamble->{'x_display_range'}     = shift @fields;
  $preamble->{'x_display_origin'}    = shift @fields;
  $preamble->{'y_display_range'}     = shift @fields;
  $preamble->{'y_display_origin'}    = shift @fields;
  $preamble->{'date'}                = shift @fields;
  $preamble->{'time'}                = shift @fields;
  $preamble->{'frame_model_#'}       = shift @fields;
  $preamble->{'module_#'}            = shift @fields;
  $preamble->{'acquisition_mode'}    = shift @fields;
  $preamble->{'completion'}          = shift @fields;
  $preamble->{'x_units'}             = shift @fields;
  $preamble->{'y_units'}             = shift @fields;
  $preamble->{'max_bandwidth_limit'} = shift @fields;
  $preamble->{'min_bandwidth_limit'} = shift @fields;
  ###preambles added beyond what the box gives...
  # these are wrong
  #$preamble->{'x_cartesian_range'}	= $preamble->{ 'x_display_range' };
  #$preamble->{'x_cartesian_origin'}	= $preamble->{ 'x_display_origin' };
  #$preamble->{'y_cartesian_range'}	= -1 * $preamble->{ 'y_display_range' };
  #$preamble->{'y_cartesian_origin'}	= $preamble->{ 'y_display_origin' }
  #					    - $preamble->{ 'y_display_range' };
  $preamble->{'y_index_max'} = 320;
  $preamble->{'x_index_max'} = 450;
  ###end of added preambles beyond what the box gives...
  $preamble->{'format'} = (
    $preamble->{'format'} == 0 ? 'ASCII'
    : (
      $preamble->{'format'} == 1 ? 'BYTE'
      : ( $preamble->{'format'} == 2 ? 'WORD' : 'LONG' )
    )
  );
  $preamble->{'type'} = (
    $preamble->{'type'} == 1 ? 'RAW'
    : (
      $preamble->{'type'} == 2 ? 'AVG'
      : (
        $preamble->{'type'} == 3 ? 'VHIST'
        : (
          $preamble->{'type'} == 4 ? 'HHIST'
          : (
            $preamble->{'type'} == 5 ? 'VERSUS'
            : ( $preamble->{'type'} == 8 ? 'DATABASE' : 'UNKNOWN' )
          )
        )
      )
    )
  );
  $preamble->{'acquisition_mode'} =
    ( $preamble->{'acquisition_mode'} == 2 ? 'SEQUENTIAL' : 'UNKNOWN' );
  $preamble->{'x_units'} = (
    $preamble->{'x_units'} == 0 ? 'UNKNOWN'
    : (
      $preamble->{'x_units'} == 1 ? 'VOLT'
      : (
        $preamble->{'x_units'} == 2 ? 'SECOND'
        : (
          $preamble->{'x_units'} == 3 ? 'CONSTANT'
          : (
            $preamble->{'x_units'} == 4 ? 'AMP'
            : (
              $preamble->{'x_units'} == 5 ? 'DECIBEL'
              : (
                $preamble->{'x_units'} == 6 ? 'HITS'
                : (
                  $preamble->{'x_units'} == 7 ? 'PERCENT'
                  : (
                    $preamble->{'x_units'} == 8 ? 'WATTS'
                    : (
                      $preamble->{'x_units'} == 9 ? 'OHMS'
                      : (
                        $preamble->{'x_units'} == 10 ? 'PERCENT_REFLECTION'
                        : 'GAIN'
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  );
  $preamble->{'y_units'} = (
    $preamble->{'y_units'} == 0 ? 'UNKNOWN'
    : (
      $preamble->{'y_units'} == 1 ? 'VOLT'
      : (
        $preamble->{'y_units'} == 2 ? 'SECOND'
        : (
          $preamble->{'y_units'} == 3 ? 'CONSTANT'
          : (
            $preamble->{'y_units'} == 4 ? 'AMP'
            : (
              $preamble->{'y_units'} == 5 ? 'DECIBEL'
              : (
                $preamble->{'y_units'} == 6 ? 'HITS'
                : (
                  $preamble->{'y_units'} == 7 ? 'PERCENT'
                  : (
                    $preamble->{'y_units'} == 8 ? 'WATTS'
                    : (
                      $preamble->{'y_units'} == 9 ? 'OHMS'
                      : (
                        $preamble->{'y_units'} == 10 ? 'PERCENT_REFLECTION'
                        : 'GAIN'
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  );

  # several other translations are available...
  return $preamble;
}

sub _Block2Integer {

  # Copy a FMB formatted buffer into an integer vector.
  # Assume data is transmitted in LSB order.
  # Inputs: Contents of FMB buffer (string)
  # Outputs: Reference to integer (scalar array)
  # Return 0 for success, else non-0
  my $bytebuffer = shift;                              # contents of FMB buffer
  my $ivec       = shift;                              # reference to Integer array
  my $bdigits    = chr( unpack 'xC', $bytebuffer );    # count of digits to
                                                       # express the number
                                                       # of bytes that follow

  # $digit;                                        # holds each digit
  # of count in turn
  my $bytecount;                             # the assembled
                                             # byte count from
                                             # the digits
  foreach my $digit                          # construct the
    ( unpack "xxc$bdigits", $bytebuffer )    # bytecount:
  {
    $bytecount .= chr($digit);
  };                                         # digit by digit
  my $iveccount = $bytecount / 2;            # there are 2 bytes
                                             # per integer number.
  @$ivec = unpack(
    "s$iveccount",                           # iveccount signed
                                             # 16-bit integers
                                             # presumed LSB-first
    substr(
      $bytebuffer,                           # ...from the buffer
      2 + $bdigits,                          # ...starting at
      $bytecount
    )                                        # ...this long
  );
  return 0;                                  # success
}

sub Get_Waveform_Data {

  # returns a 2x2 array of integer values: graticule[x][y]
  # one value for each pixel in the graticule
  # xmin is 0, xmax is 450, ymin is 0, ymax is 320 (451x321)
  # data is organized into cartesian coordinates;
  # (xmin,ymin) is lower left, (xmax,ymax) is upper right
  # (this is NOT the screen coordinate system)
  # xmin corresponds to xorigin, ymin corresponds to yorigin
  # xmax corresponds to xorigin + (450 * xincrement)
  # ymax corresponds to yorigin + (320 * yincrement)
  my $self = shift;                 # instrument handle
  my (%args) = ( RUN => 50, @_ );
  my ( $block, $blocksize, $ivec, $data, $mode, $run );
  $mode = uc( $args{MODE} );
  $run  = $args{RUN};
  $self->iwrite(':SYST:MODE?');
  $mode = $self->iread();
  chomp $mode;
  $self->iwrite(':SYSTEM:HEADER OFF');

  #hold( "Get_waveform_data: Set_waveform_source has been called" );
  #print "Get_waveform_data: mode is $mode\n";
  # unpack will want the data to have been entered in little-endian order
  $self->iwrite(':WAVeform:BYTeorder LSBFirst');

  # database downloads only support word formatted data (16-bit integers)
  $self->iwrite(':WAVeform:FORMat WORD');

  #$self->iwrite(':WAVeform:FORMat BYTE');
  if ( $mode eq 'OSC' ) {    # for Oscope_mode
    print "Get_waveform_data for OSC mode not completely developed\n";
    $self->iwrite(':ACQUIRE:COUNT 8');
    $self->iwrite(':ACQUIRE:POINTS 500');
    $self->iwrite(':DIGITIZE');
  }
  if ( $mode eq 'EYE' ) {    # for EYE_mode
                             #$self->iwrite(':ACQ:RUNT OFF');

    #$self->EYE_mode();
    #$self->Clear_Display();
    #$self->Ch_Display( 4, 0 );
    #$self->Ch_Display( 3, 1 );
    # now take the data
    $self->iwrite(':RUN');

    # this helps to get more hits
    $self->Run_Until( 'WAV', $run );

    #hold( 'Get_waveform_data: waveform data is now on screen' );
    # The following seems to apply to EyeMode, not ScopeMode
    # load the waveform data
    # this is a block data transfer
    # 451 * 321 integers
    # 16 bits per integer
    # this makes for 289,542 8-bit bytes
    # which will have a preamble '#6289542';
    # ... this is another 8 bytes (64 bits)
    # and a final 8-bit terminator for good luck
    # all of which yields a grand total of 289,622 bits
    $blocksize = 289622;
    $self->iwrite(':WAVeform:DATA?');
    $block = $self->iread($blocksize);
    $ivec  = [];                         # origin of integer vector
    _Block2Integer( $block, $ivec );
    $data = [];                          # origin of data array

    # organize the vector into the 2x2 array, cartesian
    my ( $i, $v );
    $i = 0;
    for my $x ( 0 .. 450 ) {
      $v = $data->[$x] = [];
      for my $y ( 0 .. 320 ) {
        $v->[ 320 - $y ] = $ivec->[ $i++ ];
      }
    }

    #hold( 'Get_waveform_data: waveform data is now collected' );
  }    # end of EYE mode
  return $data;
}

sub Get_Graticule {

  # returns a 2x2 array of integer values: graticule[x][y]
  # also returns the preamble information as a hash
  my $self = shift;                          # instrument handle
  my (%args) = ( SOURCE => 'CGRADE', @_ );
  my ( $preamble, $graticule );

  # select the source database
  Set_Waveform_Source( $self, $args{SOURCE} );

  #print "get_graticule done with set_waveform_source\n";
  # obtain the database characteristics
  $preamble = Get_Waveform_Preamble($self);

  #print "get_graticule done with get_waveform_preamble\n";
  # read and organize the data
  $graticule = Get_Waveform_Data( $self, @_ );

  #print 'graticule 0,0 is ', $graticule->[0][0], "\n";
  # provide the results
  return ( $preamble, $graticule );
}
###############################################################################
#
# Local()
#   This function returns front panel control to user
#
###############################################################################
sub Local {    # Return control to user
  my ($self) = shift;
  $self->ilocal();
}
###############################################################################
#
# Development from cb_Agilent86100A.pm
#
###############################################################################
###############################################################################
#
# DutyCycle2
#
###############################################################################
sub DutyCycle2 {
  my ($self)   = shift;
  my ($ch)     = shift;           # Note channel to take meas on
  my ($action) = shift || "?";    # Note channel to take meas on
  if ( $action =~ /\?|q/i ) {
    $self->iwrite(":MEAS:STAT ON");
    $self->iwrite(":MEAS:SEND 1");
    $self->iwrite(":MEAS:RES?");
    my ($string) = $self->iread();
    chomp($string);
    my (@data)   = split /,/, $string;
    my ($meas_n) = ( $#data + 1 ) / 8;
    for my $idx ( 0 .. $meas_n - 1 ) {
      next unless $data[ $idx * 8 ] =~ /Duty cycle\($ch\)/;
      $self->{"duty$ch"} = $data[ $idx * 8 + 5 ];
    }
    $self->iwrite(":MEAS:STAT OFF");
    $self->iwrite(":MEAS:SEND 0");
    return $self->{"duty$ch"};    # Return to value user
  } else {
    $self->iwrite(":MEAS:DUTY CHAN$ch");
  }
}
###############################################################################
#
# Query Rise Time
#
###############################################################################
sub Trise2 {
  my ($self)   = shift;
  my ($ch)     = shift;           # Note channel to take meas on
  my ($action) = shift || "?";    # Note channel to take meas on
  if ( $action =~ /\?|q/i ) {
    $self->iwrite(":MEAS:STAT ON");
    $self->iwrite(":MEAS:SEND 1");
    $self->iwrite(":MEAS:RES?");
    my ($string) = $self->iread();
    chomp($string);
    my (@data)   = split /,/, $string;
    my ($meas_n) = ( $#data + 1 ) / 8;
    for my $idx ( 0 .. $meas_n - 1 ) {
      next unless $data[ $idx * 8 ] =~ /Rise time\($ch\)/;
      $self->{"tr$ch"} = $data[ $idx * 8 + 5 ];
    }
    $self->iwrite(":MEAS:STAT OFF");
    $self->iwrite(":MEAS:SEND 0");
    return $self->{"tr$ch"};    # Return to value user
  } else {
    $self->iwrite(":MEAS:RIS CHAN$ch");
  }
}
###############################################################################
#
# Amplitude voltage (Vtop-Vbase)
#
###############################################################################
sub Vampl2 {
  my ($self)   = shift;
  my ($ch)     = shift;           # Note channel to take meas on
  my ($action) = shift || "?";    # Note channel to take meas on
  if ( $action =~ /\?|q/i ) {
    $self->iwrite(":MEAS:STAT ON");
    $self->iwrite(":MEAS:SEND 1");
    $self->iwrite(":MEAS:RES?");
    my ($string) = $self->iread();
    chomp($string);
    my (@data)   = split /,/, $string;
    my ($meas_n) = ( $#data + 1 ) / 8;
    for my $idx ( 0 .. $meas_n - 1 ) {
      next unless $data[ $idx * 8 ] =~ /V amptd\($ch\)/;
      $self->{"vampl$ch"} = $data[ $idx * 8 + 5 ];
    }
    $self->iwrite(":MEAS:STAT OFF");
    $self->iwrite(":MEAS:SEND 0");
    return $self->{"vampl$ch"};    # Return to value user
  } else {
    $self->iwrite(":MEAS:VAMP CHAN$ch");
  }
}
###############################################################################
#
#  Sub Vtop_measure
#  Set up the Vtop measurement
#  The top 40% of the measurement histogram is scanned to find the peak value
#  that is used for V top.
#
###############################################################################
sub Vtop_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Channel or source to take meas on
  $self->iwrite(":MEAS:VTOP CHAN$ch");
}
###############################################################################
#
# Waveform Top voltage
#
###############################################################################
sub Vtop {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  $self->iwrite(":MEAS:VTOP? CHAN$ch");
  $self->{"vtop$ch"} = $self->iread();
  chomp( $self->{"vtop$ch"} );
  return $self->{"vtop$ch"};    # Return to value user
}
###############################################################################
#
#  Sub Vbase_measure
#  Set up the Vbase measurement
#  The bottom 40% of the measurement histogram is scanned to find the peak value
#  that is used for V base.
#  Oscilloscope Amplitude Mode
#
###############################################################################
sub Vbase_measure {
  my ($self) = shift;
  my ($ch)   = shift;    # Channel or source to take meas on
  $self->iwrite(":MEAS:VBAS CHAN$ch");
}
###############################################################################
#
# Waveform Bottom voltage
#
###############################################################################
sub Vbase {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  $self->iwrite(":MEAS:VBASE? CHAN$ch");
  $self->{"vbase$ch"} = $self->iread();
  chomp( $self->{"vbase$ch"} );
  return $self->{"vbase$ch"};    # Return to value user
}
###############################################################################
#
# Jitter_RMS2
#
###############################################################################
sub Jitter_Start {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
  my ($par)  = shift;    # Note channel to take meas on
  $par = 'RMS' if ( $par =~ /rms/i );
  $par = 'PP'  if ( $par =~ /pp/i );
  $self->iwrite(":MEAS:CGR:JITT $par,CHAN$ch");
}
##############################################################################
#
# Sub Meas_Result: Collect the data with the state SEND 1
# This routine doens't work with Deltatime measurement (use Statistic_Meas).
# Usage: $result = $dca->Meas_Result($ch);
#	 $rise_time_mean = $result->{"Rise time($ch)"}->{mean};
#	 		    $val  ->{ $hk            }->{mean}
#
##############################################################################

=dev
  sub Meas_Result {
    my($self)=shift;
    my($ch)  =shift;            # Note channel to take meas on
    #my @par = (@_);			# remaining params are parameter names
    my %val;

    if ( defined( $ch ) ) {
      my $dch =( $ch == 1 ? "CHAN1" :
                 ( $ch == 2 ? "CHAN2" :
                   ( $ch == 3 ? "CHAN3" :
                     ( $ch == 4 ? "CHAN4" : $ch )
                   )
                 )
               );

      #$self->iwrite(":DIGITIZE $dch");
    }

    $self->iwrite(":MEAS:SEND 1"); 
    $self->iwrite(":MEAS:RES?");   
    my($string)=$self->iread();    
    chomp($string);                
    $self->iwrite(":MEAS:SEND 0"); 


    #print "$string\n\n";
    my(@data)=split /,/,$string;
    #my($meas_n)=($#data+1)/8;
    #for my $idx (0..$meas_n-1) {
    #	next unless $data[$idx*8] =~ /Duty cycle\($ch\)/;
    #        $self->{"duty$ch"}=$data[$idx*8+5];
    #    }

    # this block assumes that limit test is off and sendvalid is on
    while ( defined( $data[0] ) ) {
      #print "meas_result got '$data[0]'\n";
      my $hk = $data[0];        #$data[0] is always the name of the measurement
      # be careful here; shifts occur before assignment to $val{ $hk }
      $val{ $hk } = {
                     name	=> shift @data,
                     result	=> shift @data,
                     valid	=> shift @data,
                     minimum	=> shift @data,
                     maximum	=> shift @data,
                     mean	=> shift @data,
                     sdev	=> shift @data,
                     n_samp	=> shift @data,
                    };
      
      #print "$hk has n_samp of ", $val{ $hk }->{ name }, $val{ $hk }->{ n_samp }, "\n";
    }

    return \%val;               # Return to value user %val is a hash of hashes
  }
=cut

#=dev
sub Meas_Result {
  my ($self) = shift;
  my ($ch)   = shift;    # Note channel to take meas on
                         #my @par = (@_);			# remaining params are parameter names
  my %val;
  if ( defined($ch) ) {
    my $dch = (
      $ch == 1 ? "CHAN1"
      : (
        $ch == 2 ? "CHAN2"
        : (
          $ch == 3 ? "CHAN3"
          : ( $ch == 4 ? "CHAN4" : $ch )
        )
      )
    );
    ###$self->iwrite(":DIGITIZE $dch");
  }

  #    $self->iwrite(":MEAS:STAT ON");
  $self->iwrite(":MEAS:SEND 1");
  $self->iwrite(":MEAS:RES?");
  my ($string) = $self->iread();
  chomp($string);

  #    $self->iwrite(":MEAS:STAT OFF");
  $self->iwrite(":MEAS:SEND 0");

  #print "$string\n\n";
  my (@data) = split /,/, $string;

  #my($meas_n)=($#data+1)/8;
  #for my $idx (0..$meas_n-1) {
  #	next unless $data[$idx*8] =~ /Duty cycle\($ch\)/;
  #        $self->{"duty$ch"}=$data[$idx*8+5];
  #    }
  # this block assumes that limit test is off and sendvalid is on
  while ( defined( $data[0] ) ) {

    #print "meas_result got '$data[0]'\n";
    my $hk = $data[0];

    # be careful here; shifts occur before assignment to $val{ $hk }
    $val{$hk} = {
      name    => shift @data,
      result  => shift @data,
      valid   => shift @data,
      minimum => shift @data,
      maximum => shift @data,
      mean    => shift @data,
      sdev    => shift @data,
      n_samp  => shift @data,
    };

    #print "$hk has n_samp of ", $val{ $hk }->{ name }, $val{ $hk }->{ n_samp }, "\n";
  }
  return \%val;    # Return to value user
}

#=cut
###############################################################################
# Top Base Definition
# Default is Auto Mode. Custom mode is not recommended in Eye Mode
# The DCA used the Top-Base Level to compute the lower, middle and upper of
# Threshold Levels.
###############################################################################
sub Top_Base() {
  my ($self) = shift;
  my ($type) = shift || "STAN";    # AUTO (STANDARD) or Custom (sybtax: '1.1;0.1')
  my ($top_volt);                  # 1.1 is the top voltage in Volt
  my ($base_volt);                 # 0.1 is the base voltage in Volt
  if ( $type =~ /stan/i ) {
    $self->iwrite(':MEAS:DEF TOPB, STAN');
    $self->iwrite(':CDIS');
    return 0;
  } else {
    ( $top_volt, $base_volt ) = split( /;/, $type );
    chomp($top_volt);
    chomp($base_volt);
    $self->iwrite(":MEAS:DEF TOPB,$top_volt,$base_volt");
  }
}
###############################################################################
# Calibrate 86108 Module !FLEXDCA COMMANDS!
###############################################################################
sub Cal108 {
  my $self = shift;
  my $mod  = $self->iquery(":SYSTEM:MODEL? SLOT1");
  if ( $mod =~ /86108/ ) {
    $self->iwrite(":CALibrate:MODule:SLOT1:START");
    my $res = $self->iOPC(30);
    $self->iwrite(":CALibrate:CONTinue");
    $res = $self->iOPC(300);
    $self->iwrite(":CALibrate:CONTinue");
  } else {
    printf("No 86108 module found!");
  }
}
###################################################
# C D R   R o l e
###################################################
sub cdrInit {
  my $self = shift;
}

sub cdrLoopOrder {
  my $self      = shift;
  my $loopOrder = shift;

  #Nothing to do.
}

sub cdrState {
  my $self = shift;
  my $on   = shift;
  if ( $on != 0 ) {
    $self->iwrite(":PTIMebase1:RSOurce INTernal;");
    $self->iwrite(":PTIMebase1:RMETHod OLINearity;");
    $self->iwrite(":PTIMebase1:STATe ON;");
    $self->iwrite(":PTIMebase1:RTReference;");
    $self->iwrite(":CRECovery1:SOURce DIFFerential");
    $self->iwrtie(":CRECovery1:LSELect:AUTomatic");
    $self->iOPC(20);
    $self->iwrite(":SYSTem:AUToscale;");
    $self->iOPC(20);
  }
}

sub cdrRate {
  my $self = shift;
  my $freq = shift;
  $self->iwrite(":CRECovery1:CRATe $freq;");
}

sub cdrLoopBW {
  my $self = shift;
  my $bw   = shift;
  $self->iwrite(":CRECovery1:CLBandwidth $bw;");
}

sub cdrRelock {
  my $self = shift;
  $self->iwrite(":CRECovery1:RELock;");
  $self->iOPC(20);
}

sub cdrLocked {
  my $self = shift;
  return ( $self->iquery(":CRECovery1:LOCKed?") );
}
__PACKAGE__->meta->make_immutable;
1;

# -*- mode: perl -*-
package Agilent_E364x;
use Moose;
use namespace::autoclean;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

has 'Vsign' => (is =>'rw', default=>1);
has 'Isign' => (is =>'rw', default=>1);


########################################################
# The following methods override those inherited from DC

sub init {
	# initialize for use as a dc resource
  my $self	= shift;

  return 0	if ( $self->{VIRTUAL} );

  $self->iconnect();
  $self->iwrite("*RST;") if ($self->{RESET}); #Get us to default state

  my $err = 'x';    # seed for first iteration
  # clear any accumulated errors
  while( $err ) {
    $self->iwrite(":SYST:ERR?");
    $err    = $self->iread( 100, 1000 );
    last if ($err =~/\+0/);	    # error 0 means buffer is empty
  }
  $self->iwrite("*CLS;");
  #
  return 0;

}

sub channel_select {
  my $self=shift;
  my $chan=shift;

  if (!($chan=~/^OUT/)) {
    $chan=$chan+0;
    $chan=sprintf("OUT%d",$chan);
  }
  $self->iwrite(":INST:SEL $chan;");
  $self->iOPC();
}

sub channel_on {	# turn on the channels
  my $self	= shift;

  	# all or none for this instrument
  $self->iwrite(":OUTP:STATE ON;");
  $self->iOPC();

  #
  return 0;

}

sub channel_off { # turn off the channels
  my $self	= shift;

  return 0	if ( $self->{VIRTUAL} );
  $self->iwrite(":OUTP:STATE OFF;");
  $self->iOPC();
  #
  return 0;

}

sub v_set {
  my $self=shift;
  my $volts=shift;

  $self->iwrite(sprintf(":VOLTAGE %g;",$volts));
  $self->iOPC();
  return(0);
}

sub i_set {
  my $self=shift;
  my $amps=shift;

  $self->iwrite(sprintf(":CURRENT %g;",$amps));
  $self->iOPC();
  return(0);
}

sub force_voltage { # force a voltage
  my $self		= shift;
  my $volts		= shift;
  my $icompliance	= shift;

  my $vforce	= $self->{Vsign} * $volts;
  my $iforce	= abs( $icompliance );	# trickery here;
  					# isn't really a compliance
  $self->iwrite(":APPLY $vforce,$iforce;");
  $self->iOPC();

  return 0;
}

sub force_amperage {	# force a current
  my $self		= shift;
  my $amps		= shift;
  my $vcompliance	= shift;

  my $vforce	= abs( $vcompliance );	# trickery here;
  					# isn't really a compliance
  my $iforce	= $self->{Isign} * $amps;
  $self->iwrite(":APPLY $vforce,$iforce;");
  $self->iOPC();
  return 0;
}

sub measure_voltage {	# measure a voltage
  my $self	= shift;

  my $volts=$self->iquery(":MEASURE:VOLT?;") + 0;
  return($self->{Vsign} * $volts);		# output the measurement
}

sub measure_amperage {	# measure a current
  my $self	= shift;

  my $amps=$self->iquery(":MEASURE:CURRENT?;") + 0;
  return($self->{Isign} * $amps);		# output the measurement
}


__PACKAGE__->meta->make_immutable;
1;

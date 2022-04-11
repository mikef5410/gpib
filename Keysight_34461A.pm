# -*- mode: perl -*-
package Keysight_34461A;
use Moose;
use namespace::autoclean;
with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors
my $instrumentMethods = {
  measureDCV        => { scpi => ":MEASURE:VOLTAGE:DC AUTO",   argtype => "NONE", queryonly => 1 },
  measureACV        => { scpi => ":MEASURE:VOLTAGE:AC AUTO",   argtype => "NONE", queryonly => 1 },
  measureCAP        => { scpi => ":MEASURE:CAP AUTO",          argtype => "NONE", queryonly => 1 },
  measureContinuity => { scpi => ":MEASURE:CONTinuity",        argtype => "NONE", queryonly => 1 },
  measureDCI        => { scpi => ":MEASURE:CURRENT:DC AUTO",   argtype => "NONE", queryonly => 1 },
  measureACI        => { scpi => ":MEASURE:CURRENT:AC AUTO",   argtype => "NONE", queryonly => 1 },
  measureDiode      => { scpi => ":MEASURE:DIODe",             argtype => "NONE", queryonly => 1 },
  measureFreq       => { scpi => ":MEASURE:FREQuency",         argtype => "NONE", queryonly => 1 },
  measurePeriod     => { scpi => ":MEASURE:PERiod",            argtype => "NONE", queryonly => 1 },
  measureRes        => { scpi => ":MEASURE:RESistance AUTO",   argtype => "NONE", queryonly => 1 },
  measure4Res       => { scpi => ":MEASURE:FRES AUTO",         argtype => "NONE", queryonly => 1 },
  smoothing         => { scpi => ":CALCulate:SMOothing:STATe", argtype => "BOOLEAN" },
  smoothingResponse =>
    { scpi => ":CALCulate:SMOothing:RESPonse", argtype => "ENUM", argcheck => [ 'SLOW', 'MEDIUM', 'FAST' ] },
  trendChart   => { scpi => ":CALCULATE:TCHart:STATe",       argtype => "BOOLEAN" },
  sampleCount  => { scpi => ":SAMPle:COUNt",                 argtype => "NUMBER" },
  stats        => { scpi => ":CALCULATe:AVERage:STATe",      argtype => "BOOLEAN" },
  statsReset   => { scpi => ":CALCULATe:AVERage:CLEAr",      argtype => "NONE" },
  initiate     => { scpi => ":INITiate:IMMediate",           argtype => "NONE" },
  getReading   => { scpi => ":READ",                         argtype => "NONE", queryonly => 1 },
  getAverage   => { scpi => ":CALCulate:AVERage:AVERage",    argtype => "NONE", queryonly => 1 },
  getStatCount => { scpi => ":CALCulate:AVERage:COUNt",      argtype => "NONE", queryonly => 1 },
  getStatMax   => { scpi => ":CALCulate:AVERage:MAXimum",    argtype => "NONE", queryonly => 1 },
  getStatMin   => { scpi => ":CALCulate:AVERage:MINimum",    argtype => "NONE", queryonly => 1 },
  getStatPTP   => { scpi => ":CALCulate:AVERage:PTPeak",     argtype => "NONE", queryonly => 1 },
  getStatSdev  => { scpi => ":CALCulate:AVERage:SDEViation", argtype => "NONE", queryonly => 1 },
};

sub init {
  my $self = shift;
  $self->instrMethods($instrumentMethods);
  $self->populateAccessors();
  return 0              if ( $self->{VIRTUAL} );
  $self->iwrite("*RST") if ( $self->{RESET} );     #Get us to default state
  my $err = 'x';                                   # seed for first iteration
                                                   # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /\+0/ );                     # error 0 means buffer is empty
  }
  $self->iwrite("*CLS");
  #
  return 0;
}

#__PACKAGE__->meta->make_immutable;
1;

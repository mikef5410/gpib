# -*- mode: perl -*-
package Keysight_M8070A_32G;
use Moose;
use namespace::autoclean;
use Exception::Class ( 'UsageError' );

use constant 'OK' => 0;
use constant 'ERR' => 1;

with( 'GPIBWrap', 'Throwable' );    #Use Try::Tiny to catch my errors

my %instrMethods = (
   jitterGlobal => { scpi => ":SOURCE:JITTer:GLOBAL:STATE 'M2.DataOut'", argtype => "BOOLEAN" },
   PJState => { scpi => ":SOURCE:JITTer:LFRequency:PERiodic:STATE 'M2.DataOut'", argtype => "BOOLEAN" },
   PJAmplitude => { scpi => ":SOURce:JITTer:LFRequency:PERiodic:AMPLitude 'M2.DataOut'", argtype => "NUMBER" },
   PJFrequency => { scpi => ":SOURce:JITTer:LFRequency:PERiodic:FREQuency 'M2.DataOut'", argtype => "NUMBER" },
   PJ1State => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:STATe 'M2.DataOut'", argtype => "BOOLEAN" },
   PJ1Amplitude => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:AMPLitude 'M2.DataOut'", argtype => "NUMBER" },
   PJ1Frequency => { scpi => ":SOURce:JITTer:HFRequency:PERiodic1:FREQuency 'M2.DataOut'", argtype => "NUMBER" },
   PJ2State => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:STATe 'M2.DataOut'", argtype => "BOOLEAN" },
   PJ2Amplitude => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:AMPLitude 'M2.DataOut'", argtype => "NUMBER" },
   PJ2Frequency => { scpi => ":SOURce:JITTer:HFRequency:PERiodic2:FREQuency 'M2.DataOut'", argtype => "NUMBER" },
   outputAmpl => { scpi => ":SOURCE:VOLT:AMPL 'M2.DataOut'", argtype => "NUMBER" },
   outputOffset => { scpi => ":SOURCE:VOLT:OFFSET 'M2.DataOut'", argtype => "NUMBER" },
   outputCoupling => { scpi => ":OUTPUT:COUPLING 'M2.DataOut'", argtype => "ENUM", argcheck => ['AC','DC'] },
   outputPolarity => { scpi => ":OUTPUT:POLARITY 'M2.DataOut'", argtype => "ENUM", argcheck => ['NORM','INV'] },
   clockFreq => { scpi => ":SOURCE:FREQ 'M1.ClkGen'", argtype => "NUMBER" },
   globalOutputsState => { scpi => ":OUTPUT:GLOBAL:STATE 'M1.System'", argtype=>"BOOLEAN" },
   outputState => { scpi => ":OUTPUT:STATE 'M2.DataOut'", argtype => "BOOLEAN" },
    );

my $onoffStateGeneric=sub {
   my $self = shift;
   my $mname = shift;
   my $on = shift;

   my $descriptor=$instrMethods{$mname};
   my $subsys = $descriptor->{scpi};
   if (! defined($on)) {
      $subsys=~s/STATE/STATE?/;
      my $state=$self->iquery($subsys);
      return($state);
   }
   $on = ($on != 0);
   $self->iwrite("$subsys,".$on);
};

my $scalarSettingGeneric = sub {
   my $self = shift;
   my $mname = shift;
   my $val = shift;

   argCheck($mname,$val);
   my $descriptor=$instrMethods{$mname};
   my $subsys=$descriptor->{scpi};
   if (! defined($val)) {
      my $val=$self->iquery(queryform($subsys));
      return($val);
   }
   $val = ($val != 0);
   $self->iwrite("$subsys,".$val);
};

sub BUILD {
   my $self = shift;
   my $args = shift;

   my $meta = __PACKAGE__->meta;
   foreach my $methodName (keys(%instrMethods)) {
      my $descriptor = $instrMethods{$methodName};
      if ($descriptor->{argtype} eq "BOOLEAN") {
         $meta->add_method($methodName => sub {
            my $s = shift;
            my $arg = shift;
            return($onoffStateGeneric->($s,$methodName,$arg));
                           });
      }
      if ($descriptor->{argtype} eq "NUMBER" || $descriptor->{argtype} eq "ENUM") {
         $meta->add_method($methodName => sub {
            my $s = shift;
            my $arg = shift;

            $arg=uc($arg) if ($descriptor->{argtype} eq "ENUM");
            return($scalarSettingGeneric->($s,$methodName,$arg));
                           } );
      }
   }

   $meta->make_immutable;
}

sub init {
  my $self = shift;

  return 0 if ( $self->{VIRTUAL} );

  $self->iconnect();
  $self->iwrite("*RST") if ( $self->{RESET} );    #Get us to default state

  my $err = 'x';                                  # seed for first iteration
                                                  # clear any accumulated errors
  while ($err) {
    $self->iwrite(":SYST:ERR?");
    $err = $self->iread( 100, 1000 );
    last if ( $err =~ /\+0/ );                    # error 0 means buffer is empty
  }
  $self->iwrite("*CLS");
  #
  return 0;

}

sub onoffStateGeneric {
   my $self = shift;
   my $subsys = shift;
   my $on = shift;
   
   if (! defined($on)) {
      $subsys=~s/STATE/STATE?/;
      my $state=$self->iquery($subsys);
      return($state);
   }
   $on = ($on != 0);
   $self->iwrite("$subsys,".$on);
}

sub scalarSettingGeneric {
   my $self = shift;
   my $subsys = shift;
   my $val = shift;

   if (! defined($val)) {
      my $val=$self->iquery(queryform($subsys));
      return($val);
   }
   $val = ($val != 0);
   $self->iwrite("$subsys,".$val);
}

sub outputsON {
  my $self = shift;
  my $on   = shift;

  $on = ( $on != 0 );
  $self->outputState($on);
  $self->globalOutputsState($on);
}

sub externalReference {
  my $self = shift;
  my $on   = shift;

  $on = ( $on != 0 );
  if ($on) {
    $self->iwrite(":TRIG:SOURCE 'M1.ClkGen',REFerence");
    $self->iwrite(":TRIG:REF:FREQ 'M1.ClkGen',REF10");
  } else {
    $self->iwrite(":TRIG:SOURCE 'M1.ClkGen',INTernal");
    $self->iwrite(":TRIG:INT:SOURCE 'M1.ClkGen',INTernal");
  }
}

sub getMuxMode {
  my $self = shift;

  my $res = $self->iquery(":SOURCE:CONFigure:MINTegration? 'M2.MuxMode'");
  chomp($res);
  chomp($res);
  my ( $a, $b, $c ) = split( ",", $res );
  return ($a);
}

sub setMuxMode {
  my $self = shift;
  my $mode = shift;    # "NONe|MUX|DMUX|BOTH"

  $self->iwrite(":SOURCE:CONFigure:MINTegration 'M2.MuxMode',$mode");
}

sub PGbitRate {
  my $self  = shift;
  my $clock = shift;

  #32G mode, PG runs at 1/2 bitrate
  if ( !defined($clock) ) {
    $clock = 2 * $self->clockFreq();

     return($clock);
  }
  $self->clockFreq($clock/2);
}

sub amplitude_cm {
   my $self = shift;
   my $vpp = shift;
   my $vcm = shift || 0;

   $self->outputOffset($vcm);
   $self->outputAmpl($vpp);
}


sub trimwhite {
   my $in = shift;
   
   $in=~s/^\s+//;
   $in=~s/\s+$//;
   $in=~s/\s+/ /;
   return($in);
}

sub queryform {
   my $in = shift;

   $in=trimwhite($in);
   if ($in=~/\s+\'/) { #A subsystem qualifier?
      $in=~s/\s+\'/? '/;
   } else {
      $in = $in . '?';
   }
   return($in);
}

sub enumCheck {
   my $var = shift;
   my $allow = shift;
   
   return(OK) if (!defined($var));
   my %all = map { $_ => 1 } @$allow;
   return(ERR) if (!exists($all{uc($var)}));
   return(OK);
}

sub argCheck {
   my $mname = shift;
   my $arg = shift;

   my $descriptor=$instrMethods{$mname};
   return(OK) if (!exists($descriptor->{argcheck}));
   if ($descriptor->{argtype} == 'ENUM') {
      enumCheck($arg,$descriptor->{argcheck}) || UsageError->throw({err=>sprintf("%s requires argument be one of %s",$mname,join(",",@{$descriptor->{argcheck}}))});
   }
   return(OK);
}
   


1;
